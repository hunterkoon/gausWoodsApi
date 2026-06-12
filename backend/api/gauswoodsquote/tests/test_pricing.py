"""
Testes do motor oficial de precificacao (Fase 1 do handoff de engenharia).

Congelam o comportamento atual de pricing.py e pricing_service.py:
qualquer mudanca de formula que altere resultado comercial deve quebrar
estes testes e ser revisada conscientemente.

Rodar:  python -m pytest DADOS/api/gauswoodsquote/tests/test_pricing.py -v
        (ou python -m unittest no mesmo caminho)
"""

import unittest

from ..pricing import pv_divisor, pv_com_desconto, abaixo_custo, calcular_mao_obra
from ..pricing_service import (
    PricingInput, PricingChapa, PricingPeca, PricingFita, calcular_pricing,
)


class TestFormulasBase(unittest.TestCase):
    def test_pv_divisor_basico(self):
        # COB 1000, margem 30% por dentro -> PV = 1000 / 0.7
        self.assertAlmostEqual(pv_divisor(1000.0, 30.0), 1000.0 / 0.7, places=6)

    def test_pv_divisor_com_imposto_e_comissao(self):
        # 30 + 10 + 5 = 45% por dentro
        self.assertAlmostEqual(pv_divisor(1000.0, 30.0, 10.0, 5.0), 1000.0 / 0.55, places=6)

    def test_pv_divisor_cap_95(self):
        # soma > 95% e limitada a 95%
        self.assertAlmostEqual(pv_divisor(100.0, 90.0, 10.0, 10.0), 100.0 / 0.05, places=6)

    def test_pv_divisor_cob_zero(self):
        self.assertEqual(pv_divisor(0.0, 30.0), 0.0)

    def test_pv_com_desconto(self):
        self.assertAlmostEqual(pv_com_desconto(1000.0, 10.0), 900.0, places=6)
        self.assertEqual(pv_com_desconto(1000.0, 0.0), 1000.0)

    def test_abaixo_custo(self):
        self.assertTrue(abaixo_custo(99.0, 100.0))
        self.assertFalse(abaixo_custo(100.0, 100.0))
        # tolerancia de meio centavo
        self.assertFalse(abaixo_custo(99.996, 100.0))

    def test_mao_obra_automatica(self):
        # 10 pecas x 12 min / 60 * R$45 = R$ 90
        self.assertAlmostEqual(calcular_mao_obra(10, 5.0), 90.0, places=2)
        self.assertEqual(calcular_mao_obra(0, 5.0), 0.0)


def _payload_base(**overrides):
    """Cotacao de referencia: 1 chapa 2750x1850 a R$300, 2 pecas, 1 fita."""
    base = dict(
        chapas=[PricingChapa(esp=18.0, qty=1, price=300.0, w=2750.0, h=1850.0)],
        pecas=[
            PricingPeca(nome="lateral", comp=700.0, larg=400.0, esp=18.0),
            PricingPeca(nome="tampo",   comp=900.0, larg=500.0, esp=18.0),
        ],
        fitas=[PricingFita(nome="Fita 22mm", metros=10.0, valor_m=1.5, rolo_m=50.0)],
        price_ferragem=50.0,
        price_cola=10.0,
        price_frete=40.0,
        price_mao_obra=100.0,
        mao_obra_manual=True,
        margem_pct=30.0,
        imposto_pct=0.0,
        comissao_pct=0.0,
        desconto_global=0.0,
        aproveitamento_pct=60.0,
    )
    base.update(overrides)
    return PricingInput(**base)


class TestCalcularPricing(unittest.TestCase):
    def test_cenario_sem_desconto(self):
        r = calcular_pricing(_payload_base())
        # k_perda = 100/60 - 1 = 0.6667; preco_m2 = 300 / (2.75*1.85)
        pm2 = 300.0 / (2.750 * 1.850)
        cmc_esperado = round((round(0.28 * pm2, 4) + round(0.45 * pm2, 4)) * (100.0 / 60.0) + 15.0, 2)
        self.assertAlmostEqual(r.cmc, cmc_esperado, places=2)
        # COB = CMC + ferr + cola + frete + MO
        self.assertAlmostEqual(r.cob, round(r.cmc + 50.0 + 10.0 + 40.0 + 100.0, 2), places=2)
        # PV = COB / 0.7
        self.assertAlmostEqual(r.preco_venda, round(r.cob / 0.7, 2), places=2)
        self.assertEqual(r.total_com_desc, r.preco_venda)
        self.assertFalse(r.abaixo_custo)
        # CA = chapas inteiras + 1 rolo de fita + ferr + cola + frete (sem MO)
        self.assertAlmostEqual(r.total_aquisicao, round(300.0 + 50.0 * 1.5 + 50.0 + 10.0 + 40.0, 2), places=2)
        self.assertEqual(r.nr_rolos, 1)

    def test_cenario_com_desconto(self):
        r = calcular_pricing(_payload_base(desconto_global=10.0))
        self.assertAlmostEqual(r.total_com_desc, round(r.preco_venda * 0.9, 2), places=2)
        self.assertAlmostEqual(r.desconto_valor, round(r.preco_venda - r.total_com_desc, 2), places=2)

    def test_cenario_imposto_comissao(self):
        r = calcular_pricing(_payload_base(imposto_pct=10.0, comissao_pct=5.0))
        self.assertAlmostEqual(r.preco_venda, round(r.cob / (1 - 0.45), 2), places=2)

    def test_aproveitamento_baixo_gera_warning_e_cap(self):
        # aprov 30% -> k_perda bruto = 2.33, cap em 2.0
        r = calcular_pricing(_payload_base(aproveitamento_pct=30.0))
        self.assertTrue(any("Aproveitamento muito baixo" in w for w in r.warnings))
        pm2 = 300.0 / (2.750 * 1.850)
        mat = round(0.28 * pm2, 4) + round(0.45 * pm2, 4)
        self.assertAlmostEqual(r.cmc, round(mat * 3.0 + 15.0, 2), places=2)

    def test_fita_compra_por_rolo(self):
        # 60 m com rolo de 50 -> 2 rolos no CA, consumo 60*1.5 no CMC
        r = calcular_pricing(_payload_base(
            fitas=[PricingFita(nome="F", metros=60.0, valor_m=1.5, rolo_m=50.0)]))
        self.assertEqual(r.nr_rolos, 2)
        self.assertAlmostEqual(r.custo_fita, 90.0, places=2)
        self.assertAlmostEqual(r.custo_fita_aq, 150.0, places=2)

    def test_mao_obra_automatica(self):
        r = calcular_pricing(_payload_base(price_mao_obra=0.0, mao_obra_manual=False))
        self.assertTrue(r.mo_auto)
        # 2 pecas x 12 min / 60 x 45 = 18.0
        self.assertAlmostEqual(r.price_mo, 18.0, places=2)
        self.assertTrue(any("automaticamente" in w for w in r.warnings))

    def test_mao_obra_manual_zero_respeitada(self):
        r = calcular_pricing(_payload_base(price_mao_obra=0.0, mao_obra_manual=True))
        self.assertFalse(r.mo_auto)
        self.assertEqual(r.price_mo, 0.0)

    def test_override_cmc_de_cotacao_existente(self):
        # Edicao: CMC pre-calculado vem no payload e e respeitado
        r = calcular_pricing(_payload_base(custo_produto_geral=500.0))
        self.assertEqual(r.cmc, 500.0)

    def test_desconto_abaixo_custo(self):
        r = calcular_pricing(_payload_base(margem_pct=5.0, desconto_global=50.0))
        self.assertTrue(r.abaixo_custo)

    def test_edicao_sem_pecas_usa_override(self):
        # Fluxo de edicao (Fase 2): sem pecas/chapas, apenas fitas + overrides
        r = calcular_pricing(PricingInput(
            fitas=[PricingFita(nome="F", metros=10.0, valor_m=2.0, rolo_m=50.0)],
            price_ferragem=30.0, price_cola=5.0, price_frete=20.0,
            price_mao_obra=80.0, mao_obra_manual=True,
            margem_pct=30.0, desconto_global=0.0,
            custo_produto_geral=420.0,  # cpChapas + fitas, pre-calculado
        ))
        self.assertEqual(r.cmc, 420.0)
        self.assertAlmostEqual(r.cob, round(420.0 + 30.0 + 5.0 + 20.0 + 80.0, 2), places=2)
        self.assertAlmostEqual(r.preco_venda, round(r.cob / 0.7, 2), places=2)


class TestMaoObraDetalhada(unittest.TestCase):
    """Modelo rico de MO (antes so no MaxScript) agora centralizado na API."""

    def test_formula_detalhada(self):
        from ..pricing_service import MOParams
        r = calcular_pricing(_payload_base(
            price_mao_obra=0.0, mao_obra_manual=False,
            mo_params=MOParams(), n_ferragens=3))
        # pecas: 700x400 e 900x500 mm
        # metros_corte = 2*(0.7+0.4) + 2*(0.9+0.5) = 2.2 + 2.8 = 5.0 m
        # fita = 10 m; peso = (0.7*0.4*0.018 + 0.9*0.5*0.018) * 700 = (0.00504+0.0081)*700 = 9.198 kg
        esperado = round(50.0 + 2 * 2.5 + 5.0 * 0.8 + 10.0 * 0.3 + 3 * 5.0 + 9.198 * 0.2, 2)
        self.assertAlmostEqual(r.price_mo, esperado, places=2)
        self.assertTrue(r.mo_auto)
        self.assertTrue(any("modelo detalhado" in w for w in r.warnings))

    def test_sem_mo_params_usa_modelo_simplificado(self):
        r = calcular_pricing(_payload_base(price_mao_obra=0.0, mao_obra_manual=False))
        self.assertAlmostEqual(r.price_mo, 18.0, places=2)  # 2 pecas x 12min x R$45/h

    def test_mo_manual_ignora_mo_params(self):
        from ..pricing_service import MOParams
        r = calcular_pricing(_payload_base(
            price_mao_obra=123.0, mao_obra_manual=True, mo_params=MOParams()))
        self.assertEqual(r.price_mo, 123.0)
        self.assertFalse(r.mo_auto)


class TestCustosIndiretos(unittest.TestCase):
    """Fase 4: custos indiretos so entram no COB quando parametrizados."""

    def test_parametros_zerados_nao_mudam_resultado(self):
        r_sem = calcular_pricing(_payload_base())
        r_com_zero = calcular_pricing(_payload_base(
            horas_projeto=0.0, horas_fabricacao=0.0, horas_instalacao=0.0,
            custo_hora_operacional=0.0))
        self.assertEqual(r_sem.cob, r_com_zero.cob)
        self.assertEqual(r_sem.preco_venda, r_com_zero.preco_venda)
        self.assertEqual(r_com_zero.custo_indireto, 0.0)

    def test_custo_indireto_entra_no_cob(self):
        r_sem = calcular_pricing(_payload_base())
        r_com = calcular_pricing(_payload_base(
            horas_projeto=2.0, horas_fabricacao=8.0, horas_instalacao=0.0,
            custo_hora_operacional=25.0))
        self.assertAlmostEqual(r_com.custo_indireto, 250.0, places=2)
        self.assertAlmostEqual(r_com.cob, round(r_sem.cob + 250.0, 2), places=2)
        self.assertTrue(any("Custos indiretos" in w for w in r_com.warnings))

    def test_horas_sem_custo_hora_gera_warning(self):
        r = calcular_pricing(_payload_base(horas_fabricacao=8.0))
        self.assertEqual(r.custo_indireto, 0.0)
        self.assertTrue(any("nao configurado" in w for w in r.warnings))


if __name__ == "__main__":
    unittest.main()
