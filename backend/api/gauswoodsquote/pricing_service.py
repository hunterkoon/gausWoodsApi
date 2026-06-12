"""
Servico central de precificacao — Gaus Woods (v10).

Replica fielmente a logica de cnc_planilha.calcular() em formato estruturado
(Pydantic), reaproveitando as formulas de pricing.py. Nao altera nenhum
resultado existente — e o passo 1 da centralizacao do motor de calculo na API
(MaxScript continua coletando geometria; a API passa a ser a fonte oficial
do calculo monetario).
"""

from typing import List, Optional

from pydantic import BaseModel

from .pricing import (pv_divisor, pv_com_desconto, abaixo_custo,
                      calcular_mao_obra, calcular_mao_obra_detalhada)


# ---------------------------------------------------------------------------
# Schemas de entrada
# ---------------------------------------------------------------------------

class PricingChapa(BaseModel):
    esp:   float   # espessura mm
    qty:   int
    price: float
    w:     float   # largura mm
    h:     float   # altura/comprimento mm


class PricingPeca(BaseModel):
    nome:   str
    comp:   float
    larg:   float
    esp:    float
    fita_m: float = 0.0


class PricingFita(BaseModel):
    nome:   str   = "Manual"
    metros: float = 0.0
    valor_m: float = 0.0
    rolo_m: float = 50.0


class MOParams(BaseModel):
    """Coeficientes do modelo detalhado de mao de obra (aba Mao de Obra do .ms)."""
    base_fixa:       float = 50.0
    k_peca:          float = 2.5
    k_corte_m:       float = 0.8
    k_fita_m:        float = 0.3
    k_ferragem:      float = 5.0
    k_peso_kg:       float = 0.2
    densidade_kg_m3: float = 700.0


class PricingInput(BaseModel):
    chapas: List[PricingChapa] = []
    pecas:  List[PricingPeca]  = []
    fitas:  List[PricingFita]  = []   # multi-fita (substitui price_fita_m/fita_total_m quando presente)

    # Precos unitarios / custos diretos
    price_fita_m:  float = 0.0
    price_ferragem: float = 0.0
    price_cola:    float = 0.0
    price_mao_obra: float = 0.0
    price_frete:   float = 0.0

    # Fita (usado quando 'fitas' nao e informado)
    fita_total_m: float = 0.0
    fita_rolo_m:  int   = 50
    fita_nome:    str   = "Manual"

    # Overrides opcionais (vindos de cotacao existente)
    custo_fita_total:     float = 0.0   # consumo (CMC)
    custo_fita_aquisicao: float = 0.0   # rolos fechados (CA)
    custo_produto_geral:  float = 0.0   # CMC pre-calculado
    custo_operacional:    float = 0.0   # COB pre-calculado
    custo_aquisicao_geral: float = 0.0
    preco_venda:          float = 0.0
    preco_venda_final:    float = 0.0

    # Markup divisor (v10)
    margem_pct:   float = 0.0
    imposto_pct:  float = 0.0
    comissao_pct: float = 0.0
    desconto_global: float = 0.0

    # Mao de obra
    mao_obra_manual: bool = False
    # Modelo detalhado de MO (opcional): quando presente, a MO automatica usa
    # a formula por complexidade fisica (base + pecas + corte + fita + ferragens
    # + peso) em vez do modelo simplificado por tempo medio.
    mo_params:   Optional[MOParams] = None
    n_ferragens: int = 0

    # Custos indiretos (Fase 4 do handoff) — opcionais; com defaults zero o
    # resultado e identico ao modelo anterior. custo_hora_operacional pode ser
    # injetado pelo endpoint a partir de configuracoes_gerais.
    horas_projeto:          float = 0.0
    horas_fabricacao:       float = 0.0
    horas_instalacao:       float = 0.0
    custo_hora_operacional: float = 0.0

    # Aproveitamento do plano de corte
    aproveitamento_pct: float = 0.0
    waste_pct: float = 8.0

    cotacao_id: int = 0


# ---------------------------------------------------------------------------
# Schemas de saida
# ---------------------------------------------------------------------------

class PricingPecaOut(PricingPeca):
    area_m2:     float
    mat:         float
    fita_cost:   float
    subtotal:    float
    ferr_rateio: float
    cola_rateio: float
    outros:      float
    total:       float


class PricingChapaOut(PricingChapa):
    custo_base:  float
    custo_total: float
    area_m2:     float
    price_m2:    float


class PricingResult(BaseModel):
    chapas: List[PricingChapaOut]
    pecas:  List[PricingPecaOut]

    custo_chapas:      float
    custo_chapas_base: float
    custo_desp:        float
    custo_fita:        float
    custo_fita_aq:     float
    nr_rolos:          int
    fita_nome:         str
    fita_rolo:         int

    price_ferr:  float
    price_cola:  float
    price_mo:    float
    price_frete: float

    total_aquisicao: float
    cmc: float
    cob: float

    margem_pct:   float
    imposto_pct:  float
    comissao_pct: float

    preco_venda:    float
    desconto_pct:   float
    desconto_valor: float
    total_com_desc: float
    abaixo_custo:   bool

    waste_pct:  float
    fita_total: float

    cotacao_id:       int
    custo_aq_geral:   float
    custo_prod_geral: float

    mo_auto:  bool
    warnings: List[str] = []

    # Custos indiretos (Fase 4) — zero quando nao parametrizados
    custo_indireto:         float = 0.0
    custo_hora_operacional: float = 0.0


# ---------------------------------------------------------------------------
# Motor de calculo
# ---------------------------------------------------------------------------

def calcular_pricing(payload: PricingInput) -> PricingResult:
    """Calcula CA, CMC, COB, PV e alertas a partir de um payload bruto.

    Espelha cnc_planilha.calcular() — qualquer mudanca na formula de
    precificacao deve ser feita aqui E replicada (ou removida) la, ate que o
    MaxScript pare de recalcular localmente.
    """
    price_fita  = payload.price_fita_m
    price_ferr  = payload.price_ferragem
    price_cola  = payload.price_cola
    price_mo    = payload.price_mao_obra
    price_frete = payload.price_frete
    fita_total  = payload.fita_total_m
    fita_rolo   = payload.fita_rolo_m

    # Chapas: custo de aquisicao = chapas INTEIRAS consumidas pelo plano.
    chapas_out = []
    for c in payload.chapas:
        custo_base = c.qty * c.price
        area_total = c.qty * (c.w * c.h / 1e6)
        pm2 = custo_base / area_total if area_total > 0 else 0.0
        chapas_out.append(PricingChapaOut(
            **c.model_dump(),
            custo_base=round(custo_base, 2),
            custo_total=round(custo_base, 2),
            area_m2=round(area_total, 4),
            price_m2=round(pm2, 4),
        ))

    pecas_out = []
    total_mat = 0.0
    total_area = 0.0
    total_fita_m = 0.0
    for p in payload.pecas:
        area_p = p.comp * p.larg / 1e6
        pm2 = 0.0
        for c in chapas_out:
            if abs(c.esp - p.esp) < 0.5:
                pm2 = c.price_m2
                break
        mat  = round(area_p * pm2, 4)
        fita = round(p.fita_m * price_fita, 4)
        total_mat    += mat
        total_area   += area_p
        total_fita_m += p.fita_m
        pecas_out.append({
            **p.model_dump(),
            "area_m2": round(area_p, 6),
            "mat": mat, "fita_cost": fita, "subtotal": round(mat + fita, 4),
        })

    # Rateio fisico: ferragem proporcional a area; cola proporcional a fita aplicada.
    n_pecas = max(len(pecas_out), 1)
    for p in pecas_out:
        frac_area = (p["area_m2"] / total_area) if total_area > 0 else (1.0 / n_pecas)
        frac_fita = (p["fita_m"] / total_fita_m) if total_fita_m > 0 else frac_area
        p["ferr_rateio"] = round(price_ferr * frac_area, 4)
        p["cola_rateio"] = round(price_cola * frac_fita, 4)
        p["outros"] = round(p["ferr_rateio"] + p["cola_rateio"], 4)
        p["total"]  = round(p["subtotal"] + p["outros"], 4)

    custo_chapas      = sum(c.custo_base for c in chapas_out)
    custo_chapas_base = custo_chapas
    sobra_chapas      = max(0.0, custo_chapas - total_mat)

    # Fita: consumo (entra no CMC) vs aquisicao por rolo fechado (entra no CA)
    if payload.fitas:
        custo_fita = 0.0
        custo_fita_aq = 0.0
        nr_rolos = 0
        fita_total = 0.0
        for ft in payload.fitas:
            sub = ft.metros * ft.valor_m
            custo_fita += sub
            fita_total += ft.metros
            rolo_m = ft.rolo_m if ft.rolo_m > 0 else 50.0
            rolos = int((ft.metros / rolo_m) + 0.9999) if ft.metros > 0 else 0
            nr_rolos += rolos
            custo_fita_aq += rolos * rolo_m * ft.valor_m
        custo_fita = round(custo_fita, 2)
        custo_fita_aq = round(custo_fita_aq, 2)
    else:
        custo_fita    = payload.custo_fita_total if payload.custo_fita_total > 0 else round(fita_total * price_fita, 2)
        nr_rolos      = int((fita_total / fita_rolo) + 0.9999) if fita_rolo > 0 else 0
        custo_fita_aq = payload.custo_fita_aquisicao if payload.custo_fita_aquisicao > 0 else round(nr_rolos * fita_rolo * price_fita, 2)
    if custo_fita_aq < custo_fita:
        custo_fita_aq = custo_fita

    # Custo de Aquisicao = chapas inteiras + fita por rolo + ferr + cola + frete (SEM MO)
    total_aquisicao = round(custo_chapas + custo_fita_aq + price_ferr + price_cola + price_frete, 2)

    # Mao de obra automatica: quando nao informada, calcula a partir do projeto.
    # Com mo_params (coeficientes da aba Mao de Obra do .ms), usa o modelo
    # detalhado oficial; sem eles, o modelo simplificado por tempo medio.
    mo_modelo = ""
    if price_mo <= 0 and not payload.mao_obra_manual and len(pecas_out) > 0:
        if payload.mo_params is not None:
            mp = payload.mo_params
            metros_corte = sum(2.0 * (p.comp + p.larg) / 1000.0 for p in payload.pecas)
            peso_kg = sum((p.comp / 1000.0) * (p.larg / 1000.0) * (p.esp / 1000.0)
                          * mp.densidade_kg_m3 for p in payload.pecas)
            metros_fita_mo = sum(ft.metros for ft in payload.fitas) if payload.fitas else fita_total
            price_mo = calcular_mao_obra_detalhada(
                len(pecas_out), metros_corte, metros_fita_mo,
                payload.n_ferragens, peso_kg,
                base_fixa=mp.base_fixa, k_peca=mp.k_peca, k_corte_m=mp.k_corte_m,
                k_fita_m=mp.k_fita_m, k_ferragem=mp.k_ferragem, k_peso_kg=mp.k_peso_kg)
            mo_modelo = "detalhada"
        else:
            price_mo = calcular_mao_obra(len(pecas_out), total_area)
            mo_modelo = "simplificada"
        mo_auto = True
    else:
        mo_auto = False

    # CMC (material consumido) e COB (custo operacional base)
    aprov = payload.aproveitamento_pct
    k_perda = min(max(100.0 / aprov - 1.0, 0.0), 2.0) if aprov > 1.0 else 0.10
    warnings: List[str] = []
    if aprov > 0 and aprov < 50:
        warnings.append(f"Aproveitamento muito baixo ({aprov:.1f}%) — k_perda={k_perda:.2f}")
    if mo_auto:
        if mo_modelo == "detalhada":
            warnings.append(f"Mão de obra calculada automaticamente (modelo detalhado): R$ {price_mo:.2f}")
        else:
            warnings.append(f"Mão de obra calculada automaticamente: R$ {price_mo:.2f} ({len(pecas_out)} peças x 12min x R$45/h)")

    cmc_calc = round(total_mat * (1.0 + k_perda) + custo_fita, 2)
    if payload.custo_produto_geral > 0:
        cmc = payload.custo_produto_geral
        if cmc_calc > 0 and abs(cmc - cmc_calc) / cmc_calc > 0.05:
            warnings.append(f"CMC do meta ({cmc:.2f}) diverge >5% do calculado ({cmc_calc:.2f}) — usando meta")
    else:
        cmc = cmc_calc

    # Custos indiretos (Fase 4): horas x custo_hora_operacional.
    # Com horas ou custo_hora zerados, custo_indireto = 0 e o COB nao muda.
    horas_totais = payload.horas_projeto + payload.horas_fabricacao + payload.horas_instalacao
    custo_indireto = round(horas_totais * payload.custo_hora_operacional, 2)
    if horas_totais > 0 and payload.custo_hora_operacional <= 0:
        warnings.append("Horas informadas mas custo_hora_operacional nao configurado — custos indiretos nao aplicados")
    if custo_indireto > 0:
        warnings.append(f"Custos indiretos incluidos no COB: R$ {custo_indireto:.2f} ({horas_totais:.1f}h x R$ {payload.custo_hora_operacional:.2f}/h)")

    cob_calc = round(cmc + price_ferr + price_cola + price_frete + price_mo + custo_indireto, 2)
    if payload.custo_operacional > 0:
        cob = payload.custo_operacional
        if cob_calc > 0 and abs(cob - cob_calc) / cob_calc > 0.05:
            warnings.append(f"COB do meta ({cob:.2f}) diverge >5% do calculado ({cob_calc:.2f}) — usando meta")
    else:
        cob = cob_calc

    pv = payload.preco_venda if payload.preco_venda > 0 else round(
        pv_divisor(cob, payload.margem_pct, payload.imposto_pct, payload.comissao_pct), 2)

    desconto_pct = payload.desconto_global
    total_com_desc = payload.preco_venda_final if payload.preco_venda_final > 0 else round(pv_com_desconto(pv, desconto_pct), 2)
    desconto_valor = round(pv - total_com_desc, 2)
    venda_abaixo_custo = abaixo_custo(total_com_desc, cob)

    return PricingResult(
        chapas=chapas_out,
        pecas=pecas_out,
        custo_chapas=round(custo_chapas, 2),
        custo_chapas_base=round(custo_chapas_base, 2),
        custo_desp=round(sobra_chapas, 2),
        custo_fita=custo_fita,
        custo_fita_aq=custo_fita_aq,
        nr_rolos=nr_rolos,
        fita_nome=payload.fita_nome,
        fita_rolo=fita_rolo,
        price_ferr=price_ferr,
        price_cola=price_cola,
        price_mo=price_mo,
        price_frete=price_frete,
        total_aquisicao=total_aquisicao,
        cmc=cmc,
        cob=cob,
        margem_pct=payload.margem_pct,
        imposto_pct=payload.imposto_pct,
        comissao_pct=payload.comissao_pct,
        preco_venda=pv,
        desconto_pct=desconto_pct,
        desconto_valor=desconto_valor,
        total_com_desc=total_com_desc,
        abaixo_custo=venda_abaixo_custo,
        waste_pct=payload.waste_pct,
        fita_total=fita_total,
        cotacao_id=payload.cotacao_id,
        custo_aq_geral=payload.custo_aquisicao_geral,
        custo_prod_geral=payload.custo_produto_geral,
        mo_auto=mo_auto,
        warnings=warnings,
        custo_indireto=custo_indireto,
        custo_hora_operacional=payload.custo_hora_operacional,
    )
