"""
Modulo centralizado de precificacao — Gaus Woods.

Todas as formulas de markup/preco devem ser importadas daqui
para evitar divergencia entre API, planilha e bridge MaxScript.
"""


def pv_divisor(cob, margem_pct, imposto_pct=0.0, comissao_pct=0.0):
    """Markup divisor (v10): PV = COB / (1 - (margem + imposto + comissao) / 100).

    Margem, imposto e comissao sao percentuais POR DENTRO do preco de venda.
    Soma total das deducoes e limitada a 95% para evitar divisao por zero.
    """
    if cob <= 0:
        return 0.0
    soma_pct = min(margem_pct + imposto_pct + comissao_pct, 95.0)
    return cob / (1.0 - soma_pct / 100.0)


def pv_com_desconto(pv_bruto, desconto_pct):
    """Aplica desconto global ao preco de venda bruto."""
    if pv_bruto <= 0 or desconto_pct <= 0:
        return pv_bruto
    return pv_bruto * (1.0 - desconto_pct / 100.0)


def abaixo_custo(pv_final, cob, tolerancia=0.005):
    """Retorna True se o preco final esta abaixo do custo operacional."""
    return pv_final < cob - tolerancia


def calcular_mao_obra(n_pecas, area_total_m2, tempo_medio_peca_min=12.0,
                      valor_hora=45.0):
    """Calcula mao de obra automatica baseada em complexidade do projeto.

    Parametros configuraveis:
        tempo_medio_peca_min: minutos por peca (default 12 — corte+furacoes+borda)
        valor_hora: custo da hora de trabalho em R$

    Retorna o custo total de mao de obra em R$.
    """
    if n_pecas <= 0:
        return 0.0
    horas = (n_pecas * tempo_medio_peca_min) / 60.0
    return round(horas * valor_hora, 2)
