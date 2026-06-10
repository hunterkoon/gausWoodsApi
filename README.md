# gausWoodsApi
O **3ds Max CNC Cut Plan Optimizer** automatiza planos de corte para marcenaria. Converte modelos 3D em layouts 2D otimizados (Nesting) para Router CNC e seccionadoras, aplicando descontos de fitas de borda (0.45 a 3mm) e separação por espessura. Exporta para DWG/DXF e gera relatórios CSV para etiquetas com cálculo de aproveitamento de chapa.

# planoCorteMaxScript
O **3ds Max CNC Cut Plan Optimizer** automatiza planos de corte para marcenaria. Converte modelos 3D em layouts 2D otimizados (Nesting) para Router CNC e seccionadoras, aplicando descontos de fitas de borda (0.45 a 3mm) e separação por espessura. Exporta para DWG/DXF e gera relatórios CSV para etiquetas com cálculo de aproveitamento de chapa.

Otimizador de Plano de Corte CNC para 3ds Max
Um script avançado e completo em MaxScript projetado para automatizar e otimizar planos de corte de marcenaria diretamente no Autodesk 3ds Max. Ideal para projetistas de móveis, marceneiros e operadores de Router CNC / Seccionadoras, a ferramenta transforma modelos 3D em layouts 2D milimetricamente agrupados, prontos para usinagem e etiquetagem.

🚀 Principais Funcionalidades
Motor de Empacotamento Inteligente (Guillotine Packing): Opções de agrupamento em níveis (tiras horizontais ou verticais) ideais para cortes em seccionadora (sem encavalamento de fresa), ou otimização livre para máximo aproveitamento em máquinas Router CNC.

Gestão Dinâmica de Fitas de Borda: Interface dedicada para marcar quais lados da peça receberão fita de borda (C1, C2, L1, L2). O script desconta automaticamente a espessura da fita selecionada (0.45mm a 3.0mm) da medida final de corte.

Controle de Veio da Madeira: Algoritmos de orientação que permitem rotação livre (para materiais lisos) ou alinhamento forçado (para respeitar o sentido do veio de MDFs madeirados).

Separação Automática por Material: O script lê o eixo Z de cada peça e gera planos de corte isolados para cada espessura (ex: processa chapas de 15mm e fundos de 6mm simultaneamente em layouts separados).

Parâmetros de Fresagem: Campos configuráveis para Gap da fresa (distância entre peças) e margem de segurança nas bordas da chapa.

Exportação DWG Direta: Extrai e desenha automaticamente os shapes 2D (Splines) de cada peça em uma Layer exclusiva (Corte_2D_CNC) e aciona a exportação nativa para formato .DWG ou .DXF.

Relatório de Rendimento e CSV para Etiquetas: Gera um log completo no formato .CSV com as medidas finais, quantidades, nomes das peças e status das fitas de borda (pronto para softwares de impressão de etiquetas, como Argox/Zebra), além de calcular a % de aproveitamento da chapa.

🛠️ Como Utilizar
Selecione os objetos 3D do seu móvel na cena do 3ds Max.

Execute o script.

Na Fase 1, defina as dimensões da chapa, gap da fresa, regras de agrupamento e alinhamento do veio.

Na Fase 2, uma lista interativa será aberta para você configurar rapidamente as fitas de borda peça por peça, agrupadas por nome.

Clique em confirmar. O script irá achatar, medir, agrupar, exportar o arquivo DWG e fornecer a lista de corte otimizada no Listener (F11).

📋 Pré-requisitos
Autodesk 3ds Max (Testado e funcional em versões recentes).

Unidades de sistema bem definidas (o script faz conversões considerando o System Unit padrão, idealmente operando escalas convertidas para milímetros).


**MODO DE USO**
**1.0** - Selecione todos os objetos que queira incluir no plano de corte
<img width="658" height="638" alt="image" src="https://github.com/user-attachments/assets/7e120c4d-133d-4ee3-8a79-c59e85648eb5" />

**2.0** - Execute o script em "Run Script"
<img width="516" height="594" alt="image" src="https://github.com/user-attachments/assets/b6f07e13-b816-4502-b56b-3189fae7bd28" />

**3.0** - Selecione as opções de otimização para o plano de corte
<img width="535" height="720" alt="image" src="https://github.com/user-attachments/assets/8ff7b130-9ab3-4b6c-9182-f9e11a545693" />

**3.1** - Selecione as opções fitas de borda
<img width="737" height="829" alt="image" src="https://github.com/user-attachments/assets/47d334f0-b85b-4812-aa4d-8a2def351a72" />

**3.2** - Selecione "Confirmar e Gerar Plano"
<img width="881" height="354" alt="image" src="https://github.com/user-attachments/assets/c4b38b0a-27a2-440e-9bbf-b4ad4c3e10c4" />

**4.0** - Mensagem de sucesso com % de aproveitamento
<img width="366" height="249" alt="image" src="https://github.com/user-attachments/assets/b05b3435-d9f6-4ef0-9a64-6333739b7abe" />

**5.0** - Resultado final, será segmentado cada espessura de material em uma chapa diferente e adotado as opções de otimização selecionadas
caso tenha sido selecionado a opção de exportar para DWG, o plano de corte será exportado em um desenho flat.

<img width="1275" height="561" alt="image" src="https://github.com/user-attachments/assets/a5b412b6-49f4-442a-adef-e5fcd28486cc" />




