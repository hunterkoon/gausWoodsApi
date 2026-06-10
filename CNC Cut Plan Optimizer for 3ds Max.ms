clearlistener()

-- VariÃ¡veis Globais de Controle de Fase
global G_PiecesData = #()
global G_MainConfig = #()
global G_FitaTh     = 1.0
global fltFitas     = undefined
global G_PdfPecas        = #()   -- acumula dados para exportaÃ§Ã£o PDF
global G_PdfChapas       = #()   -- acumula contornos de chapas para PDF
global G_OriginalDims    = #()   -- dims brutas pÃ³s-alinhamento (BUG4 comparaÃ§Ã£o)
global G_TotalFitaMetros = 0.0   -- metros lineares de fita acumulados
global G_ChapasGrupos    = #()   -- #(espMm, qtd) agrupado por espessura para custos

-- Caminho do script definido no momento do carregamento (nÃ£o dentro de funÃ§Ã£o)
global G_ScriptDir = getFilenamePath (getThisScriptFilename())

-- ============================================================
-- API BANCO DE DADOS â€” Globais e Helpers
-- ============================================================
global G_ApiOnline       = false  -- status da API
global G_PythonExe       = ""    -- caminho do executavel Python (detectado no startup)
global G_ApiBusy         = false -- evita chamadas API aninhadas sobrescrevendo arquivos temporarios
global G_ApiLastCmd      = ""
global G_ApiLastParams   = #()
global G_ActiveSpinner      = undefined  -- label de spinner ativo durante chamada API
global G_ActiveDadosClienteDlg = undefined  -- referencia ao rollout rlDadosCliente aberto
global G_ActiveCustoRl         = undefined  -- referencia ao rollout rlCusto aberto
global G_ActiveCotacoesRl      = undefined  -- referencia ao rollout rlCotacoes aberto
global G_FerragemDialogOnClose = undefined  -- callback invocado ao fechar rlBuscaFerragem (modeless)
global G_CotFiltroClienteId   = 0          -- cliente selecionado como filtro na tela de cotacoes
global G_CotFiltroClienteNome = ""         -- nome exibido no filtro
global G_FCliResults          = #()        -- resultados temporarios do filtro de clientes em cotacoes
global G_ApiChapaPrecos  = #()   -- #(espMm, valor, nome_produto, acabamento, largura_mm, comprimento_mm, valor_m2) por espessura
global G_ApiFitaPrecos   = #()   -- #(acabamento, valor_m_linear, nome_produto, tamanho_rolo_m, valor_rolo) por acabamento
global G_BuscaChapaEspMm = 0.0
global G_BuscaFitaAcabamento = ""
global G_FitasMultiLinhas   = #()  -- array de #(nome, metros, valor_m, rolo_m, fornecedor) por linha de fita
global G_FerragensLista     = #()  -- array de #(id, nome, valor, fornecedor, qtd) por ferragem selecionada
global G_BuscaFitaTargetRow = 1    -- indice da linha de fita sendo editada no modal de busca

-- ============================================================
-- MAO DE OBRA — coeficientes do modelo de pre-calculo
-- Configurados em rlConfig > aba "Mao de Obra", persistidos em INI
-- ============================================================
global G_MO_IniPath   = (getDir #userScripts) + "\\cnc_mo_config.ini"
global G_MO_BasFixa   = 50.0    -- valor base fixo (R$) independente do projeto
global G_MO_KPeca     = 2.5     -- R$ por peca distinta
global G_MO_KCorteM   = 0.8     -- R$ por metro linear de corte
global G_MO_KFita     = 0.3     -- R$ por metro de fita aplicada
global G_MO_KFerragem       = 5.0     -- R$ por ferragem
global G_MO_KPeso           = 0.2     -- R$ por kg estimado
global G_MO_Densidade       = 700.0   -- kg/m3 (MDF/MDP medio)
global G_MO_KPerdaSeguranca = 0.10   -- fator de perda CNC (8-12%); aplicado ao CMC_Chapas
-- Referencias globais aos campos de texto da aba Mao de Obra (rlConfig).
-- Necessario porque dotNetObject criado dentro de fn buildMaoObra fica no escopo
-- local da funcao — sem esses globais, onAdvance ve txtMOBase = undefined e o
-- try-catch engole o erro sem atualizar G_MO_*.
global G_TxtMOBase   = undefined
global G_TxtMOKPeca  = undefined
global G_TxtMOKCorte = undefined
global G_TxtMOKFita  = undefined
global G_TxtMOKFerr  = undefined
global G_TxtMOKPeso  = undefined
global G_TxtMODens   = undefined
global G_TxtMOKPerda = undefined

-- ============================================================
-- TEMA VISUAL: aplica acabamento claro e consistente a todos os controles
-- Chame na abertura de qualquer rollout/dialog:
--   try ( ::aplicarTemaForm anyDotNetControl.FindForm() ) catch()
-- ============================================================
fn aplicarTemaForm frm =
(
    local Color        = dotNetClass "System.Drawing.Color"
    local FontStyle    = dotNetClass "System.Drawing.FontStyle"
    local BorderStyle  = dotNetClass "System.Windows.Forms.BorderStyle"
    local FlatStyle    = dotNetClass "System.Windows.Forms.FlatStyle"
    local corFundo     = Color.FromArgb 245 246 248
    local corPainel    = Color.FromArgb 250 250 252
    local corCampo     = Color.FromArgb 255 255 255
    local corBotao     = Color.FromArgb 229 233 238
    local corBotaoOver = Color.FromArgb 218 224 232
    local corPesquisar = Color.FromArgb  43 116 199
    local corPesqOver  = Color.FromArgb  31  99 174
    local corProximo   = Color.FromArgb  46 139  87
    local corProxOver  = Color.FromArgb  36 119  73
    local corAtualizar = Color.FromArgb 232 135  32
    local corAtualOver = Color.FromArgb 209 112  22
    local corCancelar  = Color.FromArgb 196  63  57
    local corCancOver  = Color.FromArgb 170  49  45
    local corBorda     = Color.FromArgb 205 211 219
    local corGrid      = Color.FromArgb 224 228 234
    local corTexto     = Color.FromArgb  27  32  38
    local corTextoSuave= Color.FromArgb  91 101 113
    local corLinhaA    = Color.FromArgb 248 250 252
    local fonteBase    = dotNetObject "System.Drawing.Font" "Segoe UI" 9.0
    local fonteTitulo  = dotNetObject "System.Drawing.Font" "Segoe UI" 9.0 (FontStyle.Bold)
    local fonteBotao   = dotNetObject "System.Drawing.Font" "Segoe UI" 9.0 (FontStyle.Bold)
    local clsBtn       = dotNetClass "System.Windows.Forms.Button"
    local clsTxt       = dotNetClass "System.Windows.Forms.TextBox"
    local clsDGV       = dotNetClass "System.Windows.Forms.DataGridView"
    local clsCmb       = dotNetClass "System.Windows.Forms.ComboBox"
    local clsGrp       = dotNetClass "System.Windows.Forms.GroupBox"
    local clsLbl       = dotNetClass "System.Windows.Forms.Label"
    local clsPanel     = dotNetClass "System.Windows.Forms.Panel"
    local clsTab       = dotNetClass "System.Windows.Forms.TabControl"
    local clsTabPage   = dotNetClass "System.Windows.Forms.TabPage"
    local clsCheck     = dotNetClass "System.Windows.Forms.CheckBox"

    try ( frm.BackColor = corFundo ) catch()
    try ( frm.Font = fonteBase ) catch()

    -- BFS: percorre toda a arvore de controles
    local fila = #()
    try ( for i = 0 to (frm.Controls.Count - 1) do append fila (frm.Controls.Item i) ) catch()

    local idx = 1
    while idx <= fila.count do
    (
        local ctrl = fila[idx]; idx += 1
        -- Adiciona filhos
        try ( for j = 0 to (ctrl.Controls.Count - 1) do append fila (ctrl.Controls.Item j) ) catch()

        try (
            if clsDGV.IsInstanceOfType ctrl then
            (
                ctrl.BackgroundColor                            = corCampo
                ctrl.GridColor                                  = corGrid
                ctrl.DefaultCellStyle.BackColor                 = corCampo
                ctrl.DefaultCellStyle.ForeColor                 = corTexto
                ctrl.DefaultCellStyle.SelectionBackColor        = corPesquisar
                ctrl.DefaultCellStyle.SelectionForeColor        = Color.White
                ctrl.AlternatingRowsDefaultCellStyle.BackColor  = corLinhaA
                ctrl.ColumnHeadersDefaultCellStyle.BackColor    = Color.FromArgb 236 240 245
                ctrl.ColumnHeadersDefaultCellStyle.ForeColor    = corTexto
                ctrl.ColumnHeadersDefaultCellStyle.Font         = fonteTitulo
                ctrl.EnableHeadersVisualStyles                  = false
                ctrl.BorderStyle                                = BorderStyle.FixedSingle
                ctrl.RowTemplate.Height                         = 26
            )
            else if clsBtn.IsInstanceOfType ctrl then
            (
                local t = toLower ctrl.Text
                local n = ""
                try ( n = toLower ctrl.Name ) catch()
                local isBack   = (findString t "voltar"   != undefined)
                local isCancel = (not isBack) and ((findString t "cancelar" != undefined) or (findString t "fechar" != undefined) or (findString n "cancel" != undefined) or (findString n "close" != undefined))
                local isUpdate = (findString t "atualizar" != undefined) or (findString n "atualizar" != undefined)
                local isSearch = (findString t "pesquisar" != undefined) or (findString t "buscar" != undefined) or (findString n "search" != undefined) or (findString n "buscar" != undefined)
                local isNext = (findString t "avancar" != undefined) or (findString t "proximo" != undefined) or (findString t "confirmar" != undefined) or (findString t "criar" != undefined) or (findString t "gerar" != undefined) or (findString t "salvar" != undefined) or (findString t "usar" != undefined) or (findString t "selecionar" != undefined) or (findString t "iniciar" != undefined) or (findString n "avan" != undefined) or (findString n "go" != undefined) or (findString n "confirm" != undefined) or (findString n "criar" != undefined) or (findString n "salvar" != undefined) or (findString n "usar" != undefined) or (findString n "start" != undefined)
                ctrl.Font      = fonteBotao
                ctrl.FlatStyle = FlatStyle.Flat
                try ( ctrl.UseVisualStyleBackColor = false ) catch()
                ctrl.FlatAppearance.BorderSize = 1
                if isCancel then
                (
                    ctrl.BackColor = corCancelar
                    ctrl.ForeColor = Color.White
                    ctrl.FlatAppearance.BorderColor = corCancelar
                    ctrl.FlatAppearance.MouseOverBackColor = corCancOver
                    ctrl.FlatAppearance.MouseDownBackColor = Color.FromArgb 145 39 36
                )
                else if isUpdate then
                (
                    ctrl.BackColor = corAtualizar
                    ctrl.ForeColor = Color.White
                    ctrl.FlatAppearance.BorderColor = corAtualizar
                    ctrl.FlatAppearance.MouseOverBackColor = corAtualOver
                    ctrl.FlatAppearance.MouseDownBackColor = Color.FromArgb 183 93 18
                )
                else if isSearch then
                (
                    ctrl.BackColor = corPesquisar
                    ctrl.ForeColor = Color.White
                    ctrl.FlatAppearance.BorderColor = corPesquisar
                    ctrl.FlatAppearance.MouseOverBackColor = corPesqOver
                    ctrl.FlatAppearance.MouseDownBackColor = Color.FromArgb 24 78 142
                )
                else if isNext then
                (
                    ctrl.BackColor = corProximo
                    ctrl.ForeColor = Color.White
                    ctrl.FlatAppearance.BorderColor = corProximo
                    ctrl.FlatAppearance.MouseOverBackColor = corProxOver
                    ctrl.FlatAppearance.MouseDownBackColor = Color.FromArgb 26 99 60
                )
                else
                (
                    ctrl.BackColor = corBotao
                    ctrl.ForeColor = corTexto
                    ctrl.FlatAppearance.BorderColor = corBorda
                    ctrl.FlatAppearance.MouseOverBackColor = corBotaoOver
                    ctrl.FlatAppearance.MouseDownBackColor = Color.FromArgb 207 214 223
                )
            )
            else if clsTxt.IsInstanceOfType ctrl then
            (
                ctrl.BackColor  = corCampo
                ctrl.ForeColor  = corTexto
                ctrl.Font       = fonteBase
                ctrl.BorderStyle = BorderStyle.FixedSingle
            )
            else if clsCmb.IsInstanceOfType ctrl then
            (
                ctrl.BackColor = corCampo
                ctrl.ForeColor = corTexto
                ctrl.Font      = fonteBase
                ctrl.FlatStyle = FlatStyle.Flat
                try ( ctrl.DropDownStyle = (dotNetClass "System.Windows.Forms.ComboBoxStyle").DropDown ) catch()
                try ( if ctrl.SelectedIndex >= 0 do ctrl.Text = ctrl.Items.Item[ctrl.SelectedIndex] ) catch()
            )
            else if clsGrp.IsInstanceOfType ctrl then
            (
                ctrl.BackColor = corPainel
                ctrl.ForeColor = corPrimaria
                ctrl.Font      = fonteTitulo
                try ( ctrl.Padding = dotNetObject "System.Windows.Forms.Padding" 10 8 10 10 ) catch()
            )
            else if (clsPanel.IsInstanceOfType ctrl) or (clsTabPage.IsInstanceOfType ctrl) then
            (
                ctrl.BackColor = corFundo
                ctrl.ForeColor = corTexto
                ctrl.Font      = fonteBase
            )
            else if clsTab.IsInstanceOfType ctrl then
            (
                ctrl.BackColor = corFundo
                ctrl.ForeColor = corTexto
                ctrl.Font      = fonteTitulo
            )
            else if clsCheck.IsInstanceOfType ctrl then
            (
                ctrl.BackColor = corFundo
                ctrl.ForeColor = corTexto
                ctrl.Font      = fonteBase
            )
            else if clsLbl.IsInstanceOfType ctrl then
            (
                if ctrl.Height <= 3 then
                (
                    ctrl.BackColor = corBorda
                    ctrl.ForeColor = corBorda
                )
                else
                (
                    local parentIsGroup = false
                    try ( parentIsGroup = clsGrp.IsInstanceOfType ctrl.Parent ) catch()
                    ctrl.BackColor = (if parentIsGroup then corPainel else corFundo)
                    ctrl.ForeColor = corTextoSuave
                    ctrl.Font      = fonteBase
                )
            )
            else
            (
                ctrl.BackColor = corFundo
                ctrl.ForeColor = corTexto
                ctrl.Font      = fonteBase
            )
        ) catch()
    )
)

fn pintarBotaoAcao btn corBase corHover corDown =
(
    local Color = dotNetClass "System.Drawing.Color"
    local FlatStyle = dotNetClass "System.Windows.Forms.FlatStyle"
    try ( btn.UseVisualStyleBackColor = false ) catch()
    try ( btn.FlatStyle = FlatStyle.Flat ) catch()
    try ( btn.BackColor = corBase ) catch()
    try ( btn.ForeColor = Color.White ) catch()
    try ( btn.FlatAppearance.BorderSize = 1 ) catch()
    try ( btn.FlatAppearance.BorderColor = corBase ) catch()
    try ( btn.FlatAppearance.MouseOverBackColor = corHover ) catch()
    try ( btn.FlatAppearance.MouseDownBackColor = corDown ) catch()
)

fn pintarBotaoPesquisar btn =
(
    local Color = dotNetClass "System.Drawing.Color"
    pintarBotaoAcao btn (Color.FromArgb 43 116 199) (Color.FromArgb 31 99 174) (Color.FromArgb 24 78 142)
)

fn pintarBotaoProximo btn =
(
    local Color = dotNetClass "System.Drawing.Color"
    pintarBotaoAcao btn (Color.FromArgb 46 139 87) (Color.FromArgb 36 119 73) (Color.FromArgb 26 99 60)
)

fn pintarBotaoAtualizar btn =
(
    local Color = dotNetClass "System.Drawing.Color"
    pintarBotaoAcao btn (Color.FromArgb 232 135 32) (Color.FromArgb 209 112 22) (Color.FromArgb 183 93 18)
)

fn pintarBotaoCancelar btn =
(
    local Color = dotNetClass "System.Drawing.Color"
    pintarBotaoAcao btn (Color.FromArgb 196 63 57) (Color.FromArgb 170 49 45) (Color.FromArgb 145 39 36)
)

-- Estrutura da PeÃ§a
struct PieceObj ( node, nome, comp, larg, esp, c1, c2, l1, l2 )

-- ============================================================
-- MAO DE OBRA — INI persistence e calculo automatico
-- ============================================================

fn loadMOConfig =
(
    local f = ::G_MO_IniPath
    local rv
    rv = getIniSetting f “MaoDeObra” “base_fixa”;   if rv != “” do try (::G_MO_BasFixa   = rv as float) catch()
    rv = getIniSetting f “MaoDeObra” “k_peca”;      if rv != “” do try (::G_MO_KPeca     = rv as float) catch()
    rv = getIniSetting f “MaoDeObra” “k_corte_m”;   if rv != “” do try (::G_MO_KCorteM   = rv as float) catch()
    rv = getIniSetting f “MaoDeObra” “k_fita”;      if rv != “” do try (::G_MO_KFita     = rv as float) catch()
    rv = getIniSetting f “MaoDeObra” “k_ferragem”;  if rv != “” do try (::G_MO_KFerragem = rv as float) catch()
    rv = getIniSetting f “MaoDeObra” “k_peso”;      if rv != “” do try (::G_MO_KPeso     = rv as float) catch()
    rv = getIniSetting f “MaoDeObra” “densidade”;        if rv != “” do try (::G_MO_Densidade       = rv as float) catch()
    rv = getIniSetting f “MaoDeObra” “k_perda_seguranca”; if rv != “” do try (::G_MO_KPerdaSeguranca = rv as float) catch()
)

fn saveMOConfig =
(
    local f = ::G_MO_IniPath
    setIniSetting f “MaoDeObra” “base_fixa”  (::G_MO_BasFixa   as string)
    setIniSetting f “MaoDeObra” “k_peca”     (::G_MO_KPeca     as string)
    setIniSetting f “MaoDeObra” “k_corte_m”  (::G_MO_KCorteM   as string)
    setIniSetting f “MaoDeObra” “k_fita”     (::G_MO_KFita     as string)
    setIniSetting f “MaoDeObra” “k_ferragem” (::G_MO_KFerragem as string)
    setIniSetting f “MaoDeObra” “k_peso”     (::G_MO_KPeso     as string)
    setIniSetting f “MaoDeObra” “densidade”          (::G_MO_Densidade       as string)
    setIniSetting f “MaoDeObra” “k_perda_seguranca”  (::G_MO_KPerdaSeguranca as string)
)

-- Pre-calcula o custo de mao de obra com base nas variaveis do plano de corte.
-- Usa os coeficientes globais G_MO_* (configurados em rlConfig > aba Mao de Obra).
fn calcularMaoObra =
(
    local kBase   = try (::G_MO_BasFixa   as float) catch 50.0
    local kPeca   = try (::G_MO_KPeca     as float) catch 2.5
    local kCorteM = try (::G_MO_KCorteM   as float) catch 0.8
    local kFita   = try (::G_MO_KFita     as float) catch 0.3
    local kFerr   = try (::G_MO_KFerragem as float) catch 5.0
    local kPeso   = try (::G_MO_KPeso     as float) catch 0.2
    local dens    = try (::G_MO_Densidade as float) catch 700.0

    -- Numero de pecas distintas no plano
    local nPecas = G_PiecesData.count

    -- Total de cortes lineares: perimetro completo da peca = 2 x (comp + larg), em metros
    local totalCortesM = 0.0
    for p in G_PiecesData do
    (
        local cM = (p.comp * 25.4) / 1000.0
        local lM = (p.larg * 25.4) / 1000.0
        totalCortesM += 2.0 * (cM + lM)
    )

    -- Metro linear de fita consumida
    local fitaMetros = 0.0
    for ft in ::G_FitasMultiLinhas do
        fitaMetros += try (ft[2] as float) catch 0.0

    -- Numero de ferragens distintas (linhas na lista)
    local nFerragens = ::G_FerragensLista.count

    -- Peso estimado total (kg)
    local pesoKg = 0.0
    for p in G_PiecesData do
    (
        local espMm = (floor (p.esp * 25.4 * 10 + 0.5)) / 10.0
        local cM    = (p.comp * 25.4) / 1000.0
        local lM    = (p.larg * 25.4) / 1000.0
        local vol   = cM * lM * (espMm / 1000.0)  -- m3
        pesoKg += vol * dens
    )

    local mo = kBase + nPecas * kPeca + totalCortesM * kCorteM + fitaMetros * kFita + nFerragens * kFerr + pesoKg * kPeso
    (floor (mo * 100.0 + 0.5)) / 100.0
)

-- Carrega config salva ao iniciar (silencioso se arquivo nao existir)
try ( ::loadMOConfig() ) catch()

-- ============================================================
-- API BANCO DE DADOS â€” ComunicaÃ§Ã£o via Python helper
-- ============================================================

-- Retorna separador de diretÃ³rio correto (movido para cÃ¡ pois usado nas fns de API)
fn dirSep path = (
    if path.count > 0 and (substring path path.count 1) != "\\" and (substring path path.count 1) != "/" then path + "\\" else path
)

fn apiLogDir =
(
    local p = (dirSep (dirSep G_ScriptDir + "DADOS")) + "logs"
    try ( makeDir p ) catch()
    dirSep p
)

fn apiAppendLog fileName msg =
(
    local f = undefined
    try ( f = openFile ((apiLogDir()) + fileName) mode:"a" ) catch()
    if f != undefined do
    (
        format "[%] %\n" (localTime as string) msg to:f
        close f
    )
)

fn apiLogPerf msg = apiAppendLog "maxscript_ui_requests.log" msg
fn apiLogError msg = apiAppendLog "maxscript_ui_errors.log" msg

fn apiWriteCmd cmd params:#() =
(
    if G_ApiBusy do
    (
        apiLogError ("apiWriteCmd bloqueado: chamada API em andamento. cmd=" + cmd)
        return false
    )
    G_ApiLastCmd    = cmd
    G_ApiLastParams = params
    local tmpDir  = dirSep sysInfo.tempDir
    local cmdFile = tmpDir + "cnc_api_cmd.txt"
    local fOut = openFile cmdFile mode:"wt"
    if fOut == undefined do return false
    format "%\n" cmd to:fOut
    for p in params do format "%\n" p to:fOut
    close fOut
    true
)

-- Detecta o executavel Python via interpretador embutido (roda uma vez no startup)
fn detectPythonExe =
(
    local tmpDir    = dirSep sysInfo.tempDir
    local exeFile   = tmpDir + "cnc_python_exe.txt"
    local tmpScript = tmpDir + "cnc_get_exe.py"
    local fOut = openFile tmpScript mode:"wt"
    if fOut == undefined do return ""
    format "import sys\nopen(r'%', 'w').write(sys.executable)\n" exeFile to:fOut
    close fOut
    python.ExecuteFile tmpScript
    if not doesFileExist exeFile do return ""
    local fIn = openFile exeFile mode:"rt"
    if fIn == undefined do return ""
    local exe = readline fIn
    close fIn
    format "Python detectado: %\n" exe
    exe
)

fn apiExecute =
(
    local t0 = timestamp()
    if G_ApiBusy do
    (
        apiLogError ("apiExecute bloqueado: chamada API em andamento. cmd=" + G_ApiLastCmd)
        return #()
    )
    G_ApiBusy = true
    local pyScript   = (dirSep G_ScriptDir) + "cnc_api_helper.py"
    local tmpDir     = dirSep sysInfo.tempDir
    local resultFile = tmpDir + "cnc_api_result.txt"
    deleteFile resultFile

    if G_PythonExe != "" then
    (
        -- Processo externo: nao bloqueia o message pump, permite spinner real
        local psi = dotNetObject "System.Diagnostics.ProcessStartInfo"
        psi.FileName        = G_PythonExe
        psi.Arguments       = "\"" + pyScript + "\""
        psi.UseShellExecute = false
        psi.CreateNoWindow  = true
        psi.WindowStyle     = (dotNetClass "System.Diagnostics.ProcessWindowStyle").Hidden

        local proc = undefined
        try ( proc = (dotNetClass "System.Diagnostics.Process").Start psi ) catch
        (
            local elapsed = timestamp() - t0
            apiLogError ("Falha ao iniciar helper Python. cmd=" + G_ApiLastCmd + " elapsed_ms=" + (elapsed as string))
            apiLogPerf  ("COMMAND command=" + G_ApiLastCmd + " status=FAIL elapsed_ms=" + (elapsed as string) + " phase=start_process")
            G_ApiBusy = false
            return #()
        )

        local spinChars = #("|", "/", "-", "\\")
        local spinIdx   = 0
        while not proc.HasExited do
        (
            spinIdx = (mod spinIdx 4) + 1
            if G_ActiveSpinner != undefined do G_ActiveSpinner.Text = spinChars[spinIdx]
            windows.processPostedMessages()
            sleep 0.08
        )
        proc.WaitForExit()
        if G_ActiveSpinner != undefined do G_ActiveSpinner.Text = ""
    )
    else
    (
        -- Fallback sem animacao: interpretador embutido
        python.ExecuteFile pyScript
        local err = python.GetLastError()
        if err != "" do
        (
            local elapsed = timestamp() - t0
            format "API Helper erro: %\n" err
            apiLogError ("API Helper erro. cmd=" + G_ApiLastCmd + " elapsed_ms=" + (elapsed as string) + " err=" + err)
            apiLogPerf  ("COMMAND command=" + G_ApiLastCmd + " status=FAIL elapsed_ms=" + (elapsed as string) + " phase=embedded_python")
            G_ApiBusy = false
            return #()
        )
    )

    local fIn = openFile resultFile mode:"rt"
    if fIn == undefined do
    (
        local elapsed = timestamp() - t0
        apiLogError ("Arquivo de resultado nao encontrado. cmd=" + G_ApiLastCmd + " elapsed_ms=" + (elapsed as string))
        apiLogPerf  ("COMMAND command=" + G_ApiLastCmd + " status=FAIL elapsed_ms=" + (elapsed as string) + " phase=read_result")
        G_ApiBusy = false
        return #()
    )
    local linhas = #()
    while not eof fIn do append linhas (readline fIn)
    close fIn
    local elapsed = timestamp() - t0
    local status = if linhas.count > 0 then linhas[1] else "EMPTY"
    apiLogPerf ("COMMAND command=" + G_ApiLastCmd + " status=" + status + " elapsed_ms=" + (elapsed as string))
    if status != "OK" do apiLogError ("API command falhou. cmd=" + G_ApiLastCmd + " status=" + status + " elapsed_ms=" + (elapsed as string) + " lines=" + (linhas as string))
    G_ApiBusy = false
    linhas
)

fn apiHealthCheck =
(
    if (apiWriteCmd "health_check") do
    (
        local res = apiExecute()
        if res.count > 0 and res[1] == "OK" do ( G_ApiOnline = true; return true )
    )
    G_ApiOnline = false
    false
)

fn apiSearchChapas nome espMin espMax subcategoria:"" page:1 =
(
    local params = #()
    if nome != ""          do append params ("nome=" + nome)
    if espMin > 0          do append params ("espessura_min=" + (espMin as string))
    if espMax > 0          do append params ("espessura_max=" + (espMax as string))
    if subcategoria != ""  do append params ("subcategoria=" + subcategoria)
    append params "limit=30"
    append params ("page=" + (page as string))

    if not (apiWriteCmd "search_chapas" params:params) do return #()
    local res = apiExecute()
    if res.count < 2 or res[1] != "OK" do return #()

    -- res[2] = total no banco (paginação), res[3+] = itens
    G_LastSearchTotal = try (res[2] as integer) catch (0)

    local items = #()
    for k = 3 to res.count do
    (
        local tok = filterString res[k] "|"
        if tok.count >= 10 do
        (
            append items #(
                tok[1] as integer,                          -- id
                tok[2],                                     -- nome
                tok[3],                                     -- subcategoria
                tok[4],                                     -- marca
                tok[5] as float,                            -- largura_mm
                tok[6] as float,                            -- comprimento_mm
                tok[7] as float,                            -- espessura_mm
                tok[8],                                     -- acabamento
                tok[9] as float,                            -- valor (R$/chapa)
                tok[10] as float,                           -- valor_m2
                if tok.count >= 11 then tok[11] else ""     -- fornecedor
            )
        )
    )
    items
)

fn apiSearchFitas nome page:1 =
(
    local params = #()
    if nome != "" do append params ("nome=" + nome)
    append params "limit=20"
    append params ("page=" + (page as string))

    if not (apiWriteCmd "search_fitas" params:params) do return #()
    local res = apiExecute()
    if res.count < 2 or res[1] != "OK" do return #()

    -- res[2] = total filtrado, res[3+] = itens
    G_LastSearchTotal = try (res[2] as integer) catch (0)

    local items = #()
    for k = 3 to res.count do
    (
        local tok = filterString res[k] "|"
        if tok.count >= 6 do
        (
            append items #(
                tok[1] as integer,                          -- id
                tok[2],                                     -- nome
                tok[3],                                     -- marca
                tok[4] as float,                            -- tamanho_rolo_m
                tok[5] as float,                            -- valor (R$/rolo)
                tok[6] as float,                            -- valor_m_linear
                if tok.count >= 7 then tok[7] else ""       -- fornecedor
            )
        )
    )
    items
)

-- ============================================================
-- API: Buscar ferragens — retorna array de #(id, nome, marca, valor, fornecedor)
-- ============================================================
fn apiSearchFerragens nome page:1 =
(
    local params = #()
    if nome != "" do append params ("nome=" + nome)
    append params ("page=" + (page as string))
    append params "limit=20"

    if not (apiWriteCmd "search_ferragens" params:params) do return #()
    local res = apiExecute()
    if res.count < 2 or res[1] != "OK" do return #()

    G_LastSearchTotal = try (res[2] as integer) catch (0)

    local items = #()
    for k = 3 to res.count do
    (
        local tok = filterString res[k] "|"
        if tok.count >= 4 do
        (
            append items #(
                try (tok[1] as integer) catch 0,            -- id
                tok[2],                                     -- nome
                tok[3],                                     -- marca
                try (tok[4] as float) catch 0.0,            -- valor
                if tok.count >= 5 then tok[5] else ""       -- fornecedor
            )
        )
    )
    items
)

fn apiSearchClientes nome =
(
    local params = #()
    if nome != "" do append params ("nome=" + nome)
    append params "limit=50"
    if not (apiWriteCmd "search_clientes" params:params) do return #()
    local res = apiExecute()
    if res.count < 2 or res[1] != "OK" do return #()
    local items = #()
    for k = 3 to res.count do
    (
        local tok = filterString res[k] "|"
        if tok.count >= 2 do
            append items #(
                try (tok[1] as integer) catch 0,
                tok[2],
                if tok.count >= 3 then tok[3] else "",
                if tok.count >= 4 then tok[4] else "",
                if tok.count >= 5 then tok[5] else "",
                if tok.count >= 6 then tok[6] else "",
                if tok.count >= 7 then tok[7] else "",
                if tok.count >= 8 then tok[8] else ""
            )
    )
    items
)

fn apiCreateCliente nome documento telefone email endereco cidade estado obs =
(
    local tmpDir      = dirSep sysInfo.tempDir
    local clienteFile = tmpDir + "cnc_cliente_data.txt"
    local ss = stringStream ""
    format "{" to:ss
    format "\"nome\":\"%\"," (substituteString nome "\"" "'") to:ss
    format "\"documento\":\"%\"," documento to:ss
    format "\"telefone\":\"%\"," telefone to:ss
    format "\"email\":\"%\"," email to:ss
    format "\"endereco\":\"%\"," (substituteString endereco "\"" "'") to:ss
    format "\"cidade\":\"%\"," cidade to:ss
    format "\"estado\":\"%\"," estado to:ss
    format "\"observacoes\":\"%\"" (substituteString obs "\"" "'") to:ss
    format "}" to:ss
    local fOut = openFile clienteFile mode:"wt"
    if fOut == undefined do return #(false, 0, "Erro ao criar arquivo")
    format "%" (ss as string) to:fOut
    close fOut
    if not (apiWriteCmd "create_cliente") do return #(false, 0, "Erro ao escrever comando")
    local res = apiExecute()
    if res.count >= 2 and res[1] == "OK" then
        #(true, try (res[2] as integer) catch 0, if res.count >= 3 then res[3] else nome)
    else
        #(false, 0, if res.count >= 2 then res[2] else "Erro desconhecido")
)

-- ============================================================
-- VALIDACAO CPF / CNPJ
-- ============================================================
fn soDigitos s =
(
    local d = ""
    for i = 1 to s.count do
        if s[i] >= "0" and s[i] <= "9" do d += s[i]
    d
)

fn validarCPF s =
(
    local d = soDigitos s
    if d.count != 11 do return false
    local allSame = true
    for i = 2 to 11 while allSame do if d[i] != d[1] do allSame = false
    if allSame do return false
    local soma = 0
    for i = 1 to 9 do soma += (d[i] as integer) * (11 - i)
    local r1 = mod (soma * 10) 11
    if r1 == 10 do r1 = 0
    if r1 != (d[10] as integer) do return false
    soma = 0
    for i = 1 to 10 do soma += (d[i] as integer) * (12 - i)
    local r2 = mod (soma * 10) 11
    if r2 == 10 do r2 = 0
    r2 == (d[11] as integer)
)

fn validarCNPJ s =
(
    local d = soDigitos s
    if d.count != 14 do return false
    local allSame = true
    for i = 2 to 14 while allSame do if d[i] != d[1] do allSame = false
    if allSame do return false
    local w1 = #(5,4,3,2,9,8,7,6,5,4,3,2)
    local soma = 0
    for i = 1 to 12 do soma += (d[i] as integer) * w1[i]
    local r1 = mod soma 11
    if r1 < 2 then r1 = 0 else r1 = 11 - r1
    if r1 != (d[13] as integer) do return false
    local w2 = #(6,5,4,3,2,9,8,7,6,5,4,3,2)
    soma = 0
    for i = 1 to 13 do soma += (d[i] as integer) * w2[i]
    local r2 = mod soma 11
    if r2 < 2 then r2 = 0 else r2 = 11 - r2
    r2 == (d[14] as integer)
)

fn validarDocumento s =
(
    local d = soDigitos s
    if d.count == 11 then validarCPF s
    else if d.count == 14 then validarCNPJ s
    else false
)

fn formatarDocumento s =
(
    local d = soDigitos s
    if d.count == 11 then
        d[1]+d[2]+d[3]+"."+d[4]+d[5]+d[6]+"."+d[7]+d[8]+d[9]+"-"+d[10]+d[11]
    else if d.count == 14 then
        d[1]+d[2]+"."+d[3]+d[4]+d[5]+"."+d[6]+d[7]+d[8]+"/"+d[9]+d[10]+d[11]+d[12]+"-"+d[13]+d[14]
    else s
)

fn apiStartServer =
(
    local params = #("script_dir=" + G_ScriptDir)
    if not (apiWriteCmd "start_api" params:params) do return false
    local res = apiExecute()
    if res.count > 0 and res[1] == "OK" do ( G_ApiOnline = true; return true )
    false
)

-- ============================================================
-- API BANCO DE DADOS â€” Criar CotaÃ§Ã£o (POST /cotacoes)
-- Monta JSON com chapas, fitas e outros custos e envia Ã  API.
-- Retorna #(ok:bool, cotacaoId:int, msg:string)
-- ============================================================
fn apiCriarCotacao chapasArr fitasArr outrosArr despPct aprovPct totalChapas totalFitas totalOutros totalGeral clienteId:0 nomeProjeto:"" previsaoEntrega:"" descontoGlobal:0.0 obsGeral:"" custoEfetivoChapas:0.0 custoEfetivoFitas:0.0 custoEfetivoOutros:0.0 custoEfetivoGeral:0.0 custoProductoChapas:0.0 custoProductoFitas:0.0 custoProductoOutros:0.0 custoProductoGeral:0.0 ferragensLista:#() pecasJson:"" maoObra:0.0 moManual:false custoAquisicaoTotal:0.0 custoMaterialConsumido:0.0 custoOperacionalBase:0.0 margemLucroPct:0.0 precoVendaFinal:0.0 impostoPct:0.0 comissaoPct:0.0 =
(
    local tmpDir      = dirSep sysInfo.tempDir
    local cotacaoFile = tmpDir + "cnc_cotacao_data.txt"

    -- Monta JSON manualmente (MAXScript nÃ£o tem json nativo)
    local ss = stringStream ""

    format "{" to:ss
    -- chapas
    format "\"chapas\":[" to:ss
    for i = 1 to chapasArr.count do
    (
        local c = chapasArr[i]
        -- c = #(espessura_mm, produto, quantidade, valor_unit, subtotal)
        format "{\"espessura_mm\":%,\"produto\":\"%\",\"quantidade\":%,\"valor_unit\":%,\"subtotal\":%" \
            c[1] c[2] c[3] c[4] c[5] to:ss
        format "}" to:ss
        if i < chapasArr.count do format "," to:ss
    )
    format "]," to:ss

    -- fitas
    format "\"fitas\":[" to:ss
    for i = 1 to fitasArr.count do
    (
        local f = fitasArr[i]
        -- f = #(produto, metros_total, valor_m, subtotal)
        format "{\"produto\":\"%\",\"metros_total\":%,\"valor_m\":%,\"subtotal\":%" \
            f[1] f[2] f[3] f[4] to:ss
        format "}" to:ss
        if i < fitasArr.count do format "," to:ss
    )
    format "]," to:ss

    -- outros
    -- outrosArr = #(ferragem, cola, mao_obra, frete)
    format "\"outros\":{\"ferragem\":%,\"cola\":%,\"mao_obra\":%,\"frete\":%}," \
        outrosArr[1] outrosArr[2] outrosArr[3] outrosArr[4] to:ss

    format "\"desperdicio_pct\":%," despPct to:ss
    format "\"aproveitamento_pct\":%," aprovPct to:ss
    format "\"total_chapas\":%," totalChapas to:ss
    format "\"total_fitas\":%," totalFitas to:ss
    format "\"total_outros\":%," totalOutros to:ss
    format "\"total_geral\":%," totalGeral to:ss
    format "\"cliente_id\":%," clienteId to:ss
    format "\"nome_projeto\":\"%\"," (substituteString nomeProjeto "\"" "'") to:ss
    format "\"previsao_entrega\":\"%\"," previsaoEntrega to:ss
    format "\"desconto_global\":%," descontoGlobal to:ss
    format "\"observacoes\":\"%\"," (substituteString obsGeral "\"" "'") to:ss
    -- Custo de Aquisicao (o que se paga pelos insumos, com desperdicio)
    format "\"custo_efetivo_chapas\":%," custoEfetivoChapas to:ss
    format "\"custo_efetivo_fitas\":%,"  custoEfetivoFitas  to:ss
    format "\"custo_efetivo_outros\":%," custoEfetivoOutros to:ss
    format "\"custo_efetivo_geral\":%,"  custoEfetivoGeral  to:ss
    -- Custo do Produto (apenas insumos consumidos — area x preco/m2, fitas, ferragens, frete)
    format "\"custo_produto_chapas\":%," custoProductoChapas to:ss
    format "\"custo_produto_fitas\":%,"  custoProductoFitas  to:ss
    format "\"custo_produto_outros\":%," custoProductoOutros to:ss
    format "\"custo_produto_geral\":%,"  custoProductoGeral  to:ss
    -- Mao de obra — custo interno separado da aquisicao
    format "\"mao_obra\":%,"        maoObra  to:ss
    format "\"mao_obra_manual\":%," (if moManual then "true" else "false") to:ss
    -- Campos modelo CMC + Markup (v9)
    format "\"custo_aquisicao_total\":%,"    custoAquisicaoTotal    to:ss
    format "\"custo_material_consumido\":%," custoMaterialConsumido to:ss
    format "\"custo_operacional_base\":%,"   custoOperacionalBase   to:ss
    format "\"margem_lucro_pct\":%,"         margemLucroPct         to:ss
    format "\"preco_venda_final\":%,"        precoVendaFinal        to:ss
    -- Campos modelo v10: imposto e comissao por dentro do preco (markup divisor)
    format "\"imposto_pct\":%,"              impostoPct             to:ss
    format "\"comissao_pct\":%,"             comissaoPct            to:ss
    -- Ferragens como JSON array
    format "\"ferragens\":[" to:ss
    for i = 1 to ferragensLista.count do
    (
        local fe = ferragensLista[i]
        -- fe = #(id, nome, valor, fornecedor, qtd)
        format "{\"id\":%,\"nome\":\"%\",\"valor_unit\":%,\"fornecedor\":\"%\",\"qtd\":%,\"subtotal\":%}" \
            fe[1] (substituteString fe[2] "\"" "'") fe[3] fe[4] fe[5] (fe[3]*fe[5]) to:ss
        if i < ferragensLista.count do format "," to:ss
    )
    format "]," to:ss
    -- Pecas cotadas como JSON embutido (já serializado)
    local pecasJsonSafe = if pecasJson == "" then "[]" else pecasJson
    format "\"pecas_json\":%" pecasJsonSafe to:ss
    format "}" to:ss

    -- Salva JSON no arquivo temporÃ¡rio
    local fOut = openFile cotacaoFile mode:"wt"
    if fOut == undefined do return #(false, 0, "Erro ao criar arquivo temporÃ¡rio")
    format "%" (ss as string) to:fOut
    close fOut

    -- Escreve comando e executa helper
    if not (apiWriteCmd "create_cotacao") do return #(false, 0, "Erro ao escrever comando")
    local res = apiExecute()

    if res.count >= 2 and res[1] == "OK" then
    (
        local cotId = res[2] as integer
        #(true, cotId, "CotaÃ§Ã£o #" + res[2] + " criada com sucesso!")
    )
    else
    (
        local msg = if res.count >= 2 then res[2] else "Erro desconhecido"
        #(false, 0, "Falha: " + msg)
    )
)

-- ============================================================
-- API: Buscar cliente por ID — retorna #(nome, doc, tel, email, cid, uf) ou #()
-- ============================================================
fn apiGetCliente clienteId =
(
    if clienteId <= 0 do return #()
    local params = #("id=" + (clienteId as string))
    if not (apiWriteCmd "get_cliente" params:params) do return #()
    local res = apiExecute()
    if res.count < 2 or res[1] != "OK" do return #()
    -- res[2]=nome, res[3]=doc, res[4]=tel, res[5]=email, res[6]=cid, res[7]=uf
    local out = #()
    for k = 2 to res.count do append out res[k]
    while out.count < 6 do append out ""
    out
)

-- ============================================================
-- API: Buscar cotacoes com filtro — retorna array de #(id, data, cli_nome, proj, total, desconto)
-- ============================================================
fn apiSearchCotacoes clienteId dataIni dataFim =
(
    local params = #()
    if clienteId > 0 do append params ("cliente_id=" + (clienteId as string))
    if dataIni  != "" do append params ("data_ini=" + dataIni)
    if dataFim  != "" do append params ("data_fim=" + dataFim)
    append params "page=1"
    append params "limit=100"
    if not (apiWriteCmd "search_cotacoes" params:params) do return #()
    local res = apiExecute()
    if res.count < 2 or res[1] != "OK" do return #()
    local items = #()
    for k = 3 to res.count do
    (
        local tok = filterString res[k] "|"
        local dataOk = false
        local totalOk = false
        if tok.count >= 6 do
        (
            dataOk = (tok[2].count >= 10 and (findString tok[2] "-" != undefined))
            try ( tok[5] as float; totalOk = true ) catch ( totalOk = false )
        )
        if tok.count >= 6 and dataOk and totalOk do
            append items #(
                try (tok[1] as integer) catch 0,   -- id
                if tok.count >= 2 then tok[2] else "",   -- data
                if tok.count >= 3 then tok[3] else "",   -- cliente_nome
                if tok.count >= 4 then tok[4] else "",   -- nome_projeto
                try (tok[5] as float) catch 0.0,          -- total_geral
                try (if tok.count >= 6 then (tok[6] as float) else 0.0) catch 0.0   -- desconto
            )
    )
    items
)

-- ============================================================
-- API: Detalhe de cotacao por ID
-- Retorna #(cliId, proj, entrega, desconto, totChapas, totFita, totOutros, totGeral, obs, aprov) ou undefined
-- ============================================================
fn apiGetCotacao cotacaoId =
(
    if cotacaoId <= 0 do return undefined
    local params = #("id=" + (cotacaoId as string))
    if not (apiWriteCmd "get_cotacao" params:params) do return undefined
    local res = apiExecute()
    if res.count < 2 or res[1] != "OK" do return undefined
    local out = #()
    for k = 2 to res.count do append out res[k]
    -- garante comprimento minimo de 28 para todos os campos v9/v10
    while out.count < 28 do append out ""
    local cliId = undefined
    try ( cliId = out[1] as integer ) catch ( cliId = undefined )
    if cliId == undefined do return undefined
    -- Retorna array alinhado: cot[k] == out[k] para k=1..26
    -- [1]=cliId  [2]=proj  [3]=entrega  [4]=desconto
    -- [5]=totChapas  [6]=totFitas  [7]=totOutros  [8]=totGeral
    -- [9]=obs  [10]=aprov
    -- [11]=custoEfetivoGeral  [12]=custoEfetivoChapas  [13]=custoEfetivoFitas
    -- [14]=custoEfetivoOutros  [15]=desperdicio_pct
    -- [16]=custoProductoGeral  [17]=custoProductoChapas  [18]=custoProductoFitas
    -- [19]=custoProductoOutros  [20]=maoObra  [21]=maoObra_manual
    -- [22]=custoAquisicaoTotal  [23]=cmc  [24]=cob  [25]=margemPct  [26]=precoVenda
    -- [27]=impostoPct  [28]=comissaoPct  (modelo v10 — por dentro do preco)
    #(
        cliId,
        out[2], out[3],
        try (out[4]  as float) catch 0.0,   -- [4]  desconto
        try (out[5]  as float) catch 0.0,   -- [5]  totChapas
        try (out[6]  as float) catch 0.0,   -- [6]  totFitas
        try (out[7]  as float) catch 0.0,   -- [7]  totOutros
        try (out[8]  as float) catch 0.0,   -- [8]  totGeral
        out[9],                              -- [9]  obs
        try (out[10] as float) catch 0.0,   -- [10] aprov
        try (out[11] as float) catch 0.0,   -- [11] custoEfetivoGeral  (fallback CA)
        try (out[12] as float) catch 0.0,   -- [12] custoEfetivoChapas
        try (out[13] as float) catch 0.0,   -- [13] custoEfetivoFitas
        try (out[14] as float) catch 0.0,   -- [14] custoEfetivoOutros
        try (out[15] as float) catch 0.0,   -- [15] desperdicio_pct
        try (out[16] as float) catch 0.0,   -- [16] custoProductoGeral (fallback CMC)
        try (out[17] as float) catch 0.0,   -- [17] custoProductoChapas
        try (out[18] as float) catch 0.0,   -- [18] custoProductoFitas
        try (out[19] as float) catch 0.0,   -- [19] custoProductoOutros
        try (out[20] as float) catch 0.0,   -- [20] maoObra
        out[21],                             -- [21] maoObra_manual (string "true"/"false")
        try (out[22] as float) catch 0.0,   -- [22] custoAquisicaoTotal (CA v9)
        try (out[23] as float) catch 0.0,   -- [23] custo_material_consumido (CMC v9)
        try (out[24] as float) catch 0.0,   -- [24] custo_operacional_base  (COB v9)
        try (out[25] as float) catch 0.0,   -- [25] margem_lucro_pct
        try (out[26] as float) catch 0.0,   -- [26] preco_venda_final
        try (out[27] as float) catch 0.0,   -- [27] imposto_pct  (v10)
        try (out[28] as float) catch 0.0    -- [28] comissao_pct (v10)
    )
)

-- ============================================================
-- API: Itens da cotacao (chapas + fitas + outros)
-- Retorna #(chapas:#(...), fitas:#(...), outros:#(...))
-- Cada chapa: #(espMm, produto, qtd, valorUnit, subtotal)
-- Cada fita:  #(produto, metros, valorM, subtotal)
-- Outros:     #(ferragem, cola, maoObra, frete)
-- ============================================================
fn apiGetCotacaoItems cotacaoId =
(
    if cotacaoId <= 0 do return undefined
    local params = #("id=" + (cotacaoId as string))
    if not (apiWriteCmd "get_cotacao_items" params:params) do return undefined
    local res = apiExecute()
    if res.count < 2 or res[1] != "OK" do return undefined

    local chapas  = #()
    local fitas   = #()
    local outros  = #(0.0, 0.0, 0.0, 0.0)
    local idx     = 2  -- res[1]=OK

    -- Numero de chapas
    local nCh = try (res[idx] as integer) catch 0; idx += 1
    for i = 1 to nCh do (
        if idx > res.count do exit
        local parts = filterString res[idx] "|"
        while parts.count < 5 do append parts ""
        append chapas #(
            try (parts[1] as float) catch 0.0,
            parts[2],
            try (parts[3] as integer) catch 0,
            try (parts[4] as float) catch 0.0,
            try (parts[5] as float) catch 0.0
        )
        idx += 1
    )

    -- Numero de fitas
    local nFt = try (res[idx] as integer) catch 0; idx += 1
    for i = 1 to nFt do (
        if idx > res.count do exit
        local parts = filterString res[idx] "|"
        while parts.count < 4 do append parts ""
        append fitas #(
            parts[1],
            try (parts[2] as float) catch 0.0,
            try (parts[3] as float) catch 0.0,
            try (parts[4] as float) catch 0.0
        )
        idx += 1
    )

    -- Outros
    if idx <= res.count do (
        local parts = filterString res[idx] "|"
        while parts.count < 4 do append parts "0"
        outros = #(
            try (parts[1] as float) catch 0.0,
            try (parts[2] as float) catch 0.0,
            try (parts[3] as float) catch 0.0,
            try (parts[4] as float) catch 0.0
        )
        idx += 1
    )

    -- Ferragens (novos campos) — #(id, nome, valorUnit, fornecedor, qtd, subtotal)
    local ferragens = #()
    if idx <= res.count do
    (
        local nFe = try (res[idx] as integer) catch 0; idx += 1
        for i = 1 to nFe do
        (
            if idx > res.count do exit
            local parts = filterString res[idx] "|"
            while parts.count < 6 do append parts ""
            append ferragens #(
                try (parts[1] as integer) catch 0,   -- id
                parts[2],                             -- nome
                try (parts[3] as float) catch 0.0,   -- valorUnit
                parts[4],                             -- fornecedor
                try (parts[5] as integer) catch 1,   -- qtd
                try (parts[6] as float) catch 0.0    -- subtotal
            )
            idx += 1
        )
    )

    -- Pecas planejadas — #(nome,compMm,largMm,espMm,qtd,areaM2,fitaM,precoM2,custoUnit,custoTotal,fitaC1,fitaC2,fitaL1,fitaL2)
    local pecas = #()
    if idx <= res.count do
    (
        local nPe = try (res[idx] as integer) catch 0; idx += 1
        for i = 1 to nPe do
        (
            if idx > res.count do exit
            local parts = filterString res[idx] "|"
            while parts.count < 14 do append parts "0"
            append pecas #(
                parts[1],                              -- [1]  nome
                try (parts[2] as float) catch 0.0,    -- [2]  comp_mm
                try (parts[3] as float) catch 0.0,    -- [3]  larg_mm
                try (parts[4] as float) catch 0.0,    -- [4]  esp_mm
                try (parts[5] as integer) catch 1,    -- [5]  qtd
                try (parts[6] as float) catch 0.0,    -- [6]  area_m2
                try (parts[7] as float) catch 0.0,    -- [7]  fita_m
                try (parts[8] as float) catch 0.0,    -- [8]  preco_m2
                try (parts[9] as float) catch 0.0,    -- [9]  custo_unit
                try (parts[10] as float) catch 0.0,   -- [10] custo_total
                parts[11] == "1",                     -- [11] fita_c1
                parts[12] == "1",                     -- [12] fita_c2
                parts[13] == "1",                     -- [13] fita_l1
                parts[14] == "1"                      -- [14] fita_l2
            )
            idx += 1
        )
    )

    #(chapas, fitas, outros, ferragens, pecas)
)

-- ============================================================
-- API: Atualiza campos da cotacao (proj, entrega, obs, desconto, cliente_id)
-- ============================================================
fn apiUpdateCotacao cotacaoId proj:undefined entrega:undefined obs:undefined desconto:undefined clienteId:undefined =
(
    if cotacaoId <= 0 do return false
    local params = #("id=" + (cotacaoId as string))
    if proj     != undefined do append params ("proj="       + proj)
    if entrega  != undefined do append params ("entrega="    + entrega)
    if obs      != undefined do append params ("obs="        + obs)
    if desconto != undefined do append params ("desconto="   + (desconto as string))
    if clienteId != undefined do append params ("cliente_id=" + (clienteId as string))
    if params.count < 2 do return false
    if not (apiWriteCmd "update_cotacao" params:params) do return false
    local res = apiExecute()
    res.count >= 1 and res[1] == "OK"
)

-- ============================================================
-- API: Atualização completa de cotação — grava JSON em arquivo e chama update_cotacao_full
-- fitasArr  = #(#(produto, metros, valorM, subtotal), ...)
-- ferragArr = #(#(id, nome, valorUnit, fornecedor, qtd, subtotal), ...)
-- outrosArr = #(ferragem_total, cola, maoObra, frete)
-- chapasArr = #(#(espMm, produto, qtd, valorUnit, subtotal), ...)
-- ============================================================
fn apiAtualizarCotacaoFull cotacaoId proj entrega obs desconto chapasArr fitasArr ferragArr outrosArr custoEfetivoChapas custoEfetivoFitas custoEfetivoOutros custoEfetivoGeral maoObra:0.0 cmcVal:0.0 cobVal:0.0 margemPct:0.0 precoVenda:0.0 caTotal:0.0 cpFitas:0.0 cpOutros:0.0 cpGeral:0.0 impostoPct:0.0 comissaoPct:0.0 =
(
    local tmpDir     = dirSep sysInfo.tempDir
    local updateFile = tmpDir + "cnc_cotacao_update.txt"
    local ss = stringStream ""

    format "{\"cotacao_id\":%," cotacaoId to:ss
    format "\"nome_projeto\":\"%\"," (substituteString proj "\"" "'") to:ss
    format "\"previsao_entrega\":\"%\"," entrega to:ss
    format "\"observacoes\":\"%\"," (substituteString obs "\"" "'") to:ss
    format "\"desconto_global\":%," desconto to:ss

    -- Chapas
    format "\"chapas\":[" to:ss
    for i = 1 to chapasArr.count do
    (
        local c = chapasArr[i]
        format "{\"espessura_mm\":%,\"produto\":\"%\",\"quantidade\":%,\"valor_unit\":%,\"subtotal\":%}" \
            c[1] (substituteString c[2] "\"" "'") c[3] c[4] c[5] to:ss
        if i < chapasArr.count do format "," to:ss
    )
    format "]," to:ss

    -- Fitas
    format "\"fitas\":[" to:ss
    for i = 1 to fitasArr.count do
    (
        local f = fitasArr[i]
        format "{\"produto\":\"%\",\"metros_total\":%,\"valor_m\":%,\"subtotal\":%}" \
            (substituteString f[1] "\"" "'") f[2] f[3] f[4] to:ss
        if i < fitasArr.count do format "," to:ss
    )
    format "]," to:ss

    -- Ferragens
    format "\"ferragens\":[" to:ss
    for i = 1 to ferragArr.count do
    (
        local fe = ferragArr[i]
        format "{\"id\":%,\"nome\":\"%\",\"valor_unit\":%,\"fornecedor\":\"%\",\"qtd\":%,\"subtotal\":%}" \
            fe[1] (substituteString fe[2] "\"" "'") fe[3] fe[4] fe[5] fe[6] to:ss
        if i < ferragArr.count do format "," to:ss
    )
    format "]," to:ss

    -- Outros
    format "\"outros\":{\"ferragem\":%,\"cola\":%,\"mao_obra\":%,\"frete\":%}," \
        outrosArr[1] outrosArr[2] outrosArr[3] outrosArr[4] to:ss

    -- Custo efetivo
    format "\"custo_efetivo_chapas\":%," custoEfetivoChapas to:ss
    format "\"custo_efetivo_fitas\":%,"  custoEfetivoFitas  to:ss
    format "\"custo_efetivo_outros\":%," custoEfetivoOutros to:ss
    format "\"custo_efetivo_geral\":%,"  custoEfetivoGeral  to:ss

    -- Custo do produto (fitas/ferragens/frete podem mudar na edicao)
    format "\"custo_produto_fitas\":%,"   cpFitas   to:ss
    format "\"custo_produto_outros\":%,"  cpOutros  to:ss
    format "\"custo_produto_geral\":%,"   cpGeral   to:ss

    -- Mao de obra e modelo CMC+Markup v9
    format "\"mao_obra\":%,"                       maoObra    to:ss
    format "\"custo_aquisicao_total\":%,"           caTotal    to:ss
    format "\"custo_material_consumido\":%,"        cmcVal     to:ss
    format "\"custo_operacional_base\":%,"          cobVal     to:ss
    format "\"margem_lucro_pct\":%,"                margemPct  to:ss
    format "\"imposto_pct\":%,"                     impostoPct to:ss
    format "\"comissao_pct\":%,"                    comissaoPct to:ss
    format "\"preco_venda_final\":%"                precoVenda to:ss
    format "}" to:ss

    -- Salva e executa
    local fOut = openFile updateFile mode:"wt"
    if fOut == undefined do return #(false, "Erro ao criar arquivo de edicao")
    format "%" (ss as string) to:fOut
    close fOut

    if not (apiWriteCmd "update_cotacao_full") do return #(false, "Erro ao escrever comando")
    local res = apiExecute()
    if res.count >= 1 and res[1] == "OK" then
        #(true, "Cotacao #" + (cotacaoId as string) + " atualizada")
    else
        #(false, if res.count >= 2 then res[2] else "Erro desconhecido")
)

-- ============================================================
-- API: Exporta cotacao como HTML e abre no browser
-- ============================================================
fn apiExportCotacaoHTML cotacaoId =
(
    if cotacaoId <= 0 do return false
    local params = #("id=" + (cotacaoId as string))
    if not (apiWriteCmd "export_cotacao_html" params:params) do return false
    local res = apiExecute()
    res.count >= 1 and res[1] == "OK"
)

-- ============================================================
-- API: Exporta proposta comercial premium para o cliente
-- ============================================================
fn apiExportPropostaClienteHTML cotacaoId =
(
    if cotacaoId <= 0 do return false
    local params = #("id=" + (cotacaoId as string))
    if not (apiWriteCmd "export_proposta_cliente_html" params:params) do return false
    local res = apiExecute()
    res.count >= 1 and res[1] == "OK"
)

-- ============================================================
-- API: Atualizar desconto de uma cotacao — retorna true/false
-- ============================================================
fn apiUpdateDescontoCotacao cotacaoId desconto =
(
    local params = #("id=" + (cotacaoId as string), "desconto=" + (desconto as string))
    if not (apiWriteCmd "update_desconto_cotacao" params:params) do return false
    local res = apiExecute()
    res.count > 0 and res[1] == "OK"
)

-- Resultados temporarios de busca (usados nos modais)
global G_TempSearchResults   = #()
global G_LastSearchTotal     = 0   -- total real no banco (paginacao)
global G_ClienteSelecionadoId   = 0
global G_ClienteSelecionadoNome = ""
global G_DadosCotacaoCliente    = #()  -- #(clienteId, nomeProjeto, obs, previsaoEntrega, descontoGlobal)

-- ============================================================
-- FUNÃ‡Ã•ES AUXILIARES GLOBAIS
-- ============================================================
fn nV v = ( local l=length v; if l>0.00001 then v/l else [1,0,0] )

fn cMul cxx cxy cxz cyy cyz czz v = (
    [cxx*v.x+cxy*v.y+cxz*v.z, cxy*v.x+cyy*v.y+cyz*v.z, cxz*v.x+cyz*v.y+czz*v.z]
)

fn calcPCA obj =
(
    local msh = snapshotAsMesh obj
    local n   = msh.numverts
    local cx=0.0; local cy=0.0; local cz=0.0
    for i=1 to n do ( local v=getVert msh i; cx+=v.x; cy+=v.y; cz+=v.z )
    cx/=n; cy/=n; cz/=n

    local cxx=0.0;local cxy=0.0;local cxz=0.0
    local cyy=0.0;local cyz=0.0;local czz=0.0
    for i=1 to n do
    (
        local v=getVert msh i; local dx=v.x-cx; local dy=v.y-cy; local dz=v.z-cz
        cxx+=dx*dx; cxy+=dx*dy; cxz+=dx*dz
        cyy+=dy*dy; cyz+=dy*dz; czz+=dz*dz
    )

    local e1=nV [1,0.1,0.05]
    for i=1 to 32 do e1=nV (cMul cxx cxy cxz cyy cyz czz e1)

    local e2s=cross e1 [0,0,1]; if (length e2s)<0.1 do e2s=cross e1 [0,1,0]
    local e2=nV e2s
    for i=1 to 32 do ( e2=nV (cMul cxx cxy cxz cyy cyz czz e2); e2=nV (e2-e1*(dot e2 e1)) )

    local e3=normalize (cross e1 e2)

    local min1=1e9; local max1=-1e9; local min2=1e9; local max2=-1e9; local min3=1e9; local max3=-1e9
    for i=1 to n do
    (
        local v = getVert msh i; local d1 = dot v e1; local d2 = dot v e2; local d3 = dot v e3
        if d1 < min1 do min1 = d1; if d1 > max1 do max1 = d1
        if d2 < min2 do min2 = d2; if d2 > max2 do max2 = d2
        if d3 < min3 do min3 = d3; if d3 > max3 do max3 = d3
    )
    delete msh

    local axes = #( #(e1, max1-min1), #(e2, max2-min2), #(e3, max3-min3) )
    if axes[1][2] < axes[2][2] do ( local t=axes[1]; axes[1]=axes[2]; axes[2]=t )
    if axes[2][2] < axes[3][2] do ( local t=axes[2]; axes[2]=axes[3]; axes[3]=t )
    if axes[1][2] < axes[2][2] do ( local t=axes[1]; axes[1]=axes[2]; axes[2]=t )

    #(axes[1][1], axes[2][1], axes[3][1])
)

fn buildAlignMatrix axes =
(
    local e1=axes[1]; local e2=axes[2]; local e3=axes[3]; if e3.z < 0 do e3 = -e3
    local newZ = normalize e3; local newX = normalize (cross e2 newZ); local newY = normalize (cross newZ newX)
    matrix3 newX newY newZ [0,0,0]
)

-- ============================================================
-- ALINHAMENTO POR NORMAL DA MAIOR FACE
-- Resolve painÃ©is em qualquer angulaÃ§Ã£o sem depender de AABB
-- ============================================================

fn getMaiorFaceNormal obj =
(
    -- Tira snapshot do mesh em estado atual (vÃ©rtices em local space)
    local msh = snapshotAsMesh obj

    -- Coleta normais com Ã¡rea acumulada por grupo de orientaÃ§Ã£o similar
    local grupos = #()   -- cada entry: #(normal_unit, area_total)

    for f = 1 to msh.numfaces do
    (
        local fi  = getFace msh f
        local v1  = getVert msh fi.x
        local v2  = getVert msh fi.y
        local v3  = getVert msh fi.z
        local cr  = cross (v2-v1) (v3-v1)
        local area = length cr
        if area < 0.00001 do continue
        local n = cr / area   -- normal unitÃ¡rio eficiente

        -- Canonicaliza: sempre aponta para o semiespaÃ§o "+Z, +Y, +X"
        -- para que frente e verso da mesma face sejam agrupados
        if (n.z < -0.0001) or \
           (abs(n.z) < 0.0001 and n.y < -0.0001) or \
           (abs(n.z) < 0.0001 and abs(n.y) < 0.0001 and n.x < -0.0001) do n = -n

        -- Agrupa com normal jÃ¡ existente (cos > 0.985 â‰ˆ < 10Â° de diferenÃ§a)
        local achou = false
        for g in grupos while not achou do
        (
            if (dot g[1] n) > 0.985 do ( g[2] += area; achou = true )
        )
        if not achou do append grupos #(n, area)
    )
    delete msh

    -- Retorna o normal do grupo de maior Ã¡rea = face plana do painel
    local bestN = [0,0,1]; local bestA = -1.0
    for g in grupos do
        if g[2] > bestA do ( bestA = g[2]; bestN = g[1] )

    -- Garante que o normal Ã© unitÃ¡rio (pode ter acumulado erros)
    local len = length bestN
    if len > 0.0001 then bestN / len else [0,0,1]
)

fn alinharPelaFaceMaior obj =
(
    local n = getMaiorFaceNormal obj

    -- Salva centro do bounding box ANTES de rotacionar
    local bb0 = nodeGetBoundingBox obj (matrix3 1)
    local ctr  = (bb0[1]+bb0[2]) * 0.5

    local worldZ = [0,0,1]
    local cosA   = dot n worldZ
    if cosA >  1.0 do cosA =  1.0
    if cosA < -1.0 do cosA = -1.0

    if cosA < 0.9999 then      -- nÃ£o estÃ¡ alinhado com Z
    (
        local cr    = cross n worldZ
        local crLen = length cr
        if crLen > 0.0001 then
        (
            local axis  = cr / crLen
            local angle = acos cosA     -- MAXScript: acos retorna GRAUS
            rotate obj (angleaxis angle axis)
        )
        else if cosA < 0 then
        (
            -- Normal apontando para -Z: vira 180Â° em X
            rotate obj (angleaxis 180 [1,0,0])
        )
    )

    -- Recentra na mesma posiÃ§Ã£o do bounding box original
    local bb1 = nodeGetBoundingBox obj (matrix3 1)
    obj.pos  += (ctr - ((bb1[1]+bb1[2]) * 0.5))

    -- Assenta o fundo exatamente em Z = 0
    local bbZ = nodeGetBoundingBox obj (matrix3 1)
    obj.pos.z -= bbZ[1].z
)

-- ============================================================
-- ESTIMATIVA DE DESPERDÃCIO
-- ============================================================
fn calcEstimativaDesperdicio nPecas nEspessuras aproveitamento =
(
    -- Base fixa: rebarbas de abertura e primeiros cortes de nivelamento
    local base = 3.0
    -- Complexidade: mais peÃ§as = mais cortes = mais chance de erro
    local nCortes      = nPecas * 2.5
    local complexidade = if (nCortes * 0.25) < 12.0 then (nCortes * 0.25) else 12.0
    -- Cada espessura adicional exige recalibraÃ§Ã£o da mÃ¡quina
    local fatorEsp  = (nEspessuras - 1) * 1.5
    -- Baixo aproveitamento sugere muitos retalhos e peÃ§as difÃ­ceis de encaixar
    local deltaAprv = 80.0 - aproveitamento
    local fatorAprv = if deltaAprv > 0 then (deltaAprv * 0.1) else 0.0
    local total = base + complexidade + fatorEsp + fatorAprv
    if total < 3.0  do total = 3.0
    if total > 25.0 do total = 25.0
    (floor (total * 10 + 0.5)) / 10.0
)

-- ============================================================
-- MOTOR DE ORDENAÃ‡ÃƒO
-- ============================================================
fn sortPiecesByName a b = (
    local res = stricmp a.nome b.nome
    if res != 0 then res
    else ( if a.comp > b.comp then -1 else if a.comp < b.comp then 1 else 0 )
)

fn sortAreaDesc a b = (
    local aA = a[2]*a[3]; local aB = b[2]*b[3]
    if aA > aB then -1 else if aA < aB then 1 else 0
)
fn sortHeightDesc a b = (
    if a[3] > b[3] then -1 else if a[3] < b[3] then 1 else ( if a[2] > b[2] then -1 else if a[2] < b[2] then 1 else 0 )
)
fn sortWidthDesc a b = (
    if a[2] > b[2] then -1 else if a[2] < b[2] then 1 else ( if a[3] > b[3] then -1 else if a[3] < b[3] then 1 else 0 )
)

-- ============================================================
-- FASE 3: MOTOR DE CORTE (Executado apÃ³s selecionar fitas)
-- Packing delegado ao Python (MAXRECTS) via JSON temporÃ¡rio
-- ============================================================

fn chamarPythonPacking rects binW binD gap allowRot =
(
    -- BUG-FIX: usa G_ScriptDir (definido no carregamento) em vez de getThisScriptFilename()
    local pyScript = (dirSep G_ScriptDir) + "cnc_packing.py"
    local tmpDir   = dirSep sysInfo.tempDir
    local tmpIn    = tmpDir + "cnc_input.txt"
    local tmpOut   = tmpDir + "cnc_output.txt"

    -- Escreve arquivo de entrada em formato simples (sem JSON)
    local fOut = openFile tmpIn mode:"wt"
    if fOut == undefined do ( messageBox ("Erro ao criar:\n" + tmpIn) title:"Erro Python"; return undefined )

    format "%\n" binW to:fOut
    format "%\n" binD to:fOut
    format "%\n" gap  to:fOut
    format "%\n" (if allowRot then 1 else 0) to:fOut
    format "%\n" rects.count to:fOut
    for i = 1 to rects.count do
        format "% % %\n" i rects[i][2] rects[i][3] to:fOut
    close fOut

    python.ExecuteFile pyScript

    local err = python.GetLastError()
    if err != "" do ( messageBox ("Erro Python:\n" + err) title:"Erro Packing"; return undefined )

    -- LÃª resultado linha a linha
    local fIn = openFile tmpOut mode:"rt"
    if fIn == undefined do ( messageBox ("Saida nao encontrada:\n" + tmpOut) title:"Erro Python"; return undefined )
    local linhas = #()
    while not eof fIn do append linhas (readline fIn)
    close fIn

    if linhas.count == 0 or linhas[1] != "OK" do
    (
        local errMsg = if linhas.count > 1 then linhas[2] else "Saida vazia"
        messageBox ("Python retornou erro:\n" + errMsg) title:"Erro Packing"
        return undefined
    )

    -- Monta array de placements: placements[id] = #(board, x, y, rotated)
    local boardsUsados = 0
    local placements   = #()
    for k = 1 to rects.count do append placements #(0, 0.0, 0.0, false)

    for k = 2 to linhas.count do
    (
        local ln = linhas[k]
        if matchPattern ln pattern:"boards_used=*" then
        (
            boardsUsados = (substring ln 13 -1) as integer
        )
        else if ln.count > 0 and not matchPattern ln pattern:"*=*" then
        (
            -- formato: id,board,x,y,rotated
            local tok = filterString ln ","
            if tok.count == 5 do
            (
                local pid = tok[1] as integer
                local brd = tok[2] as integer
                local px  = tok[3] as float
                local py  = tok[4] as float
                local rot = (tok[5] == "1")
                if pid >= 1 and pid <= placements.count do
                    placements[pid] = #(brd, px, py, rot)
            )
        )
    )

    #(boardsUsados, placements)
)

fn executarMotorDeCorte =
(
    local binW = G_MainConfig[1]; local binD = G_MainConfig[2]; local gap = G_MainConfig[3]
    local borda = G_MainConfig[4]; local expDWG = G_MainConfig[5]; local alignMode = G_MainConfig[6]
    local groupMode = G_MainConfig[7]

    local allowRot = (alignMode == 1); local forceHoriz = (alignMode == 3)
    local binW_Util = binW - (2 * borda); local binD_Util = binD - (2 * borda)

    local layerName = "Corte_2D_CNC"
    local cncLayer = LayerManager.getLayerFromName layerName
    if cncLayer == undefined do cncLayer = LayerManager.newLayerFromName layerName

    local shapes2D = #()
    local areaTotalChapas = 0.0
    local areaTotalPecas  = 0.0
    G_PdfPecas  = #()
    G_PdfChapas = #()

    local espessurasUnicas = #()
    for p in G_PiecesData do
    (
        local achou = false
        for e in espessurasUnicas do if abs(e - p.esp) < 0.1 do achou = true
        if not achou do append espessurasUnicas p.esp
    )

    local globalOffsetX = 0.0
    local totalChapasUsadas = 0

    for espAtual in espessurasUnicas do
    (
        local rects = #()

        for p in G_PiecesData do
        (
            if abs(p.esp - espAtual) < 0.1 do
            (
                local wCorte = p.comp
                local dCorte = p.larg
                local fitaSysUnit = G_FitaTh / 25.4
                if p.c1 do dCorte -= fitaSysUnit
                if p.c2 do dCorte -= fitaSysUnit
                if p.l1 do wCorte -= fitaSysUnit
                if p.l2 do wCorte -= fitaSysUnit

                if forceHoriz and dCorte > wCorte do
                (
                    local temp = wCorte; wCorte = dCorte; dCorte = temp
                    local bb = nodeGetBoundingBox p.node (matrix3 1)
                    local cR = (bb[1]+bb[2]) * 0.5; rotate p.node (angleaxis 90 [0,0,1])
                    local bbR2 = nodeGetBoundingBox p.node (matrix3 1); p.node.pos += (cR - ((bbR2[1]+bbR2[2]) * 0.5))
                    local bbZ = nodeGetBoundingBox p.node (matrix3 1); p.node.pos.z -= bbZ[1].z
                )

                areaTotalPecas += (wCorte * dCorte)
                append rects #(p.node, wCorte, dCorte, p)
            )
        )

        -- FIX-BUG3 definitivo: substitui cada cÃ³pia _MED por uma Box plana com
        -- dimensÃµes exatas de corte. Elimina QUALQUER problema de orientaÃ§Ã£o PCA.
        for i = 1 to rects.count do
        (
            local oldObj = rects[i][1]
            local p      = rects[i][4]
            local wCorte = rects[i][2]   -- jÃ¡ descontadas as fitas
            local dCorte = rects[i][3]

            -- Garante w >= d (maior dimensÃ£o no eixo X da box)
            if dCorte > wCorte do ( local t=wCorte; wCorte=dCorte; dCorte=t )

            -- Cria box plana com dimensÃµes de corte exatas (em unidades do sistema)
            local flatBox = Box width:wCorte length:dCorte height:p.esp isSelected:false
            flatBox.name      = oldObj.name
            flatBox.wirecolor = oldObj.wirecolor
            flatBox.pos       = [0.0, 0.0, 0.0]

            -- Descarta a cÃ³pia PCA (que pode ter orientaÃ§Ã£o errada)
            delete oldObj

            rects[i][1] = flatBox
            rects[i][2] = wCorte
            rects[i][3] = dCorte
        )

        local resultado = chamarPythonPacking rects binW_Util binD_Util gap allowRot
        if resultado == undefined do continue

        local boardsUsados = resultado[1]
        local placements   = resultado[2]

        -- Aplica os placements nas boxes planas
        for i = 1 to rects.count do
        (
            local obj   = rects[i][1]
            local pl    = placements[i]
            local bIdx  = pl[1]; local px = pl[2]; local py = pl[3]; local rotou = pl[4]

            if bIdx == 0 do continue

            -- RotaÃ§Ã£o 90Â° pedida pelo MAXRECTS: box jÃ¡ parte de orientaÃ§Ã£o limpa
            if rotou do
            (
                local bb = nodeGetBoundingBox obj (matrix3 1)
                local cR = (bb[1]+bb[2]) * 0.5
                rotate obj (angleaxis 90 [0,0,1])
                local bb2 = nodeGetBoundingBox obj (matrix3 1)
                obj.pos += (cR - ((bb2[1]+bb2[2]) * 0.5))
                local bbZ = nodeGetBoundingBox obj (matrix3 1)
                obj.pos.z -= bbZ[1].z
            )

            local bbNow   = nodeGetBoundingBox obj (matrix3 1)
            local actualW = abs(bbNow[2].x - bbNow[1].x)
            local actualD = abs(bbNow[2].y - bbNow[1].y)

            local ESPACO_CHAPAS = 200.0 / 25.4
            local planoOffsetY  = (bIdx - 1) * (binD + ESPACO_CHAPAS)

            obj.pos.x += ((px + borda) + globalOffsetX - bbNow[1].x)
            obj.pos.y += ((py + borda) + planoOffsetY  - bbNow[1].y)

            local origNameLen = obj.name.count - "_MED".count
            local nomeReal = if origNameLen > 0 then substring obj.name 1 origNameLen else obj.name

            -- DimensÃµes em mm para label (arredondadas a 1 casa)
            local wMm = (floor((actualW * 25.4) * 10 + 0.5)) / 10.0
            local dMm = (floor((actualD * 25.4) * 10 + 0.5)) / 10.0
            local labelTxt = nomeReal + "\n" + (wMm as string) + " x " + (dMm as string) + " mm"

            -- RetÃ¢ngulo 2D: usa dimensÃµes reais pÃ³s-rotaÃ§Ã£o, posiÃ§Ã£o jÃ¡ calculada
            local centerX = (px + borda) + globalOffsetX + actualW / 2.0
            local centerY = (py + borda) + planoOffsetY + actualD / 2.0

            local shp = Rectangle width:actualW length:actualD pos:[centerX, centerY, 0]
            shp.name = nomeReal + "_2D"; shp.wirecolor = color 0 255 0; convertToSplineShape shp
            cncLayer.addNode shp; append shapes2D shp

            -- FEATURE 1: Text nativo do Max com nome + dimensÃµes, centralizado na peÃ§a
            local menorDim  = if actualW < actualD then actualW else actualD
            local textSize  = menorDim * 0.12
            if textSize < (3.0 / 25.4) do textSize = 3.0 / 25.4   -- mÃ­nimo 3mm
            if textSize > (8.0 / 25.4) do textSize = 8.0 / 25.4   -- mÃ¡ximo 8mm
            local txtObj = Text text:labelTxt size:textSize align:#center
            txtObj.pos       = [centerX, centerY, 0.1]
            txtObj.name      = nomeReal + "_label"
            txtObj.wirecolor = color 255 255 0
            cncLayer.addNode txtObj
            append shapes2D txtObj

            -- Acumula dados para exportaÃ§Ã£o PDF (Feature 2)
            append G_PdfPecas #(nomeReal, wMm, dMm, bIdx, \
                                 (px + borda) + globalOffsetX, \
                                 (py + borda) + planoOffsetY, \
                                 globalOffsetX, espAtual)
        )

        for i = 1 to boardsUsados do
        (
            local ESPACO_CHAPAS = 200.0 / 25.4
            local planoOffsetY = (i - 1) * (binD + ESPACO_CHAPAS)
            areaTotalChapas += (binW * binD)
            totalChapasUsadas += 1

            local limitOut = Rectangle width:binW length:binD pos:[globalOffsetX + binW/2.0, planoOffsetY + binD/2.0, 0]
            limitOut.name = "Chapa_" + (espAtual as string) + "mm_" + (i as string); limitOut.wirecolor = color 255 0 0
            convertToSplineShape limitOut; cncLayer.addNode limitOut; append shapes2D limitOut

            -- Acumula dados de chapa para PDF
            local wMmChapa = (floor((binW * 25.4) * 10 + 0.5)) / 10.0
            local dMmChapa = (floor((binD * 25.4) * 10 + 0.5)) / 10.0
            local espMmChapa = (floor((espAtual * 25.4) * 10 + 0.5)) / 10.0
            append G_PdfChapas #(i, espMmChapa, wMmChapa, dMmChapa, globalOffsetX * 25.4, planoOffsetY * 25.4)
        )

        globalOffsetX += binW + (400.0 / 25.4)
    )

    -- RelatÃ³rio CSV
    local csvArr = #()
    append csvArr "Espessura_Chapa;Comprimento_Corte;Largura_Corte;Qtd;Nome;Fita_C1;Fita_C2;Fita_L1;Fita_L2"
    
    local pecasAgrupadas = #()
    for p in G_PiecesData do
    (
        local cSys = p.comp; local lSys = p.larg
        local fSys = G_FitaTh / 25.4
        if p.c1 do lSys -= fSys; if p.c2 do lSys -= fSys
        if p.l1 do cSys -= fSys; if p.l2 do cSys -= fSys
        
        local cMm = (floor((cSys * 25.4)*10+0.5))/10.0
        local lMm = (floor((lSys * 25.4)*10+0.5))/10.0
        local espMm = (floor((p.esp * 25.4)*10+0.5))/10.0
        if lMm > cMm do ( local t=cMm; cMm=lMm; lMm=t )
        
        local achou = false
        for agp in pecasAgrupadas do
        (
            if agp[1] == p.nome and agp[2] == cMm and agp[3] == lMm and agp[4] == espMm and agp[5] == p.c1 and agp[6] == p.c2 and agp[7] == p.l1 and agp[8] == p.l2 do
            (
                agp[9] += 1; achou = true; exit
            )
        )
        if not achou do append pecasAgrupadas #(p.nome, cMm, lMm, espMm, p.c1, p.c2, p.l1, p.l2, 1)
    )
    
    for agp in pecasAgrupadas do
    (
        local linha = (agp[4] as string) + ";" + (agp[2] as string) + ";" + (agp[3] as string) + ";" + (agp[9] as string) + ";" + agp[1] + ";" +
                      (if agp[5] then "Sim" else "Nao") + ";" + (if agp[6] then "Sim" else "Nao") + ";" +
                      (if agp[7] then "Sim" else "Nao") + ";" + (if agp[8] then "Sim" else "Nao")
        append csvArr linha

        -- Feature Custo: acumula metros de fita por peÃ§a (C = lados do comprimento, L = lados da largura)
        local qtd     = agp[9]
        local compMtr = agp[2] / 1000.0   -- mm â†’ metros
        local largMtr = agp[3] / 1000.0
        local fitaPeca = 0.0
        if agp[5] do fitaPeca += compMtr   -- c1
        if agp[6] do fitaPeca += compMtr   -- c2
        if agp[7] do fitaPeca += largMtr   -- l1
        if agp[8] do fitaPeca += largMtr   -- l2
        G_TotalFitaMetros += fitaPeca * qtd
    )

    print "\n=== LISTA DE CORTE OTIMIZADA PARA CNC/SECCIONADORA ==="
    for l in csvArr do format "%\n" l

    -- BUG4: ComparaÃ§Ã£o peÃ§a bruta vs corte
    -- Usa match por nome + dimensÃ£o mais prÃ³xima (corrige mÃºltiplas peÃ§as com mesmo nome)
    print "\n=== COMPARACAO DE MEDIDAS (Bruto vs Corte) ==="
    print "Nome | Bruto Comp | Bruto Larg | Corte Comp | Corte Larg | Desc.C | Desc.L"
    print "--------------------------------------------------------------------"
    for p in G_PiecesData do
    (
        local brutC = (floor (p.comp * 25.4 * 10 + 0.5)) / 10.0
        local brutL = (floor (p.larg * 25.4 * 10 + 0.5)) / 10.0
        -- Encontra o agp com mesmo nome E dimensÃ£o de corte mais prÃ³xima
        local bestAgp   = undefined
        local bestDelta = 9999999.0
        for agp in pecasAgrupadas do
        (
            if agp[1] == p.nome do
            (
                local d = abs(agp[2] - brutC) + abs(agp[3] - brutL)
                if d < bestDelta do ( bestDelta = d; bestAgp = agp )
            )
        )
        if bestAgp != undefined do
        (
            local dC = brutC - bestAgp[2]
            local dL = brutL - bestAgp[3]
            format "% | % | % | % | % | % | %\n" p.nome brutC brutL bestAgp[2] bestAgp[3] dC dL
        )
    )

    local aproveitamento = 0.0
    if areaTotalChapas > 0 do aproveitamento = (areaTotalPecas / areaTotalChapas) * 100.0

    -- Agrega chapas por espessura para o mÃ³dulo de custos
    G_ChapasGrupos = #()
    for c in G_PdfChapas do
    (
        local achou = false
        for g in G_ChapasGrupos do
            if abs(g[1] - c[2]) < 0.1 do ( g[2] += 1; achou = true; exit )
        if not achou do append G_ChapasGrupos #(c[2], 1)
    )

    if expDWG and shapes2D.count > 0 do
    (
        clearSelection(); select shapes2D
        local savePath = getSaveFileName caption:"Salvar Plano de Corte DWG" types:"AutoCAD DWG (*.dwg)|*.dwg|AutoCAD DXF (*.dxf)|*.dxf|"
        if savePath != undefined do ( exportFile savePath #noPrompt selectedOnly:true; format "Exportado DWG: %\n" savePath )
        clearSelection()
    )

    -- FEATURE 2: Exportar PDF do plano de corte
    local pdfPath = getSaveFileName caption:"Salvar Plano de Corte PDF" types:"PDF (*.pdf)|*.pdf|"
    if pdfPath != undefined do ::exportarPlanoPDF pdfPath aproveitamento totalChapasUsadas

    -- Abre UI de custo com os totais calculados
    ::abrirUICustoCompleto totalChapasUsadas aproveitamento G_TotalFitaMetros
)

-- ============================================================
-- FEATURE API: Modal de Busca de Chapas na API
-- ============================================================
fn abrirBuscaChapaAPI espIdx espMm =
(
    G_TempSearchResults = #()
    G_BuscaChapaEspMm = espMm

    rollout rlBuscaChapa "Buscar Chapa na API" width:860 height:608
    (
        dotNetControl lbInfo      "System.Windows.Forms.Label"       pos:[12,12]  width:620 height:18
        dotNetControl lbCategoria "System.Windows.Forms.Label"       pos:[12,42]  width:90  height:18
        dotNetControl cmbCategoria "System.Windows.Forms.ComboBox"   pos:[12,62]  width:140 height:24
        dotNetControl lbNome      "System.Windows.Forms.Label"       pos:[168,42] width:90  height:18
        dotNetControl txtNome     "System.Windows.Forms.TextBox"     pos:[168,62] width:520 height:24
        dotNetControl btnSearch   "System.Windows.Forms.Button"      pos:[704,60] width:140 height:28
        -- Paginacao
        dotNetControl btnPrev     "System.Windows.Forms.Button"      pos:[12,96]  width:100 height:26
        dotNetControl lbPag       "System.Windows.Forms.Label"       pos:[120,102] width:80 height:16
        dotNetControl btnNext     "System.Windows.Forms.Button"      pos:[208,96] width:100 height:26
        -- Grid e detalhes (deslocados 32px para baixo)
        dotNetControl grid        "System.Windows.Forms.DataGridView" pos:[12,130] width:832 height:330
        dotNetControl lbStatus    "System.Windows.Forms.Label"       pos:[12,470] width:832 height:18
        dotNetControl lbDetail1   "System.Windows.Forms.Label"       pos:[12,494] width:832 height:18
        dotNetControl lbDetail2   "System.Windows.Forms.Label"       pos:[12,516] width:832 height:18
        dotNetControl btnUsar     "System.Windows.Forms.Button"      pos:[608,546] width:236 height:30
        dotNetControl btnCancel   "System.Windows.Forms.Button"      pos:[12,546]  width:120 height:30
        dotNetControl btnDebug    "System.Windows.Forms.Button"      pos:[148,546] width:120 height:30
        dotNetControl lbLoad      "System.Windows.Forms.Label"       pos:[12,584]  width:832 height:16

        local suppressInitialSearch = false
        local currentPage = 1
        local pageLimit   = 30

        fn showLoading =
        (
            lbLoad.Text       = "|"
            lbLoad.Visible    = true
            btnSearch.Enabled = false
            G_ActiveSpinner   = lbLoad
            windows.processPostedMessages()
        )
        fn hideLoading =
        (
            G_ActiveSpinner   = undefined
            lbLoad.Visible    = false
            btnSearch.Enabled = true
        )

        fn dnColText name header width readOnly:true =
        (
            local col = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"
            col.Name = name
            col.HeaderText = header
            col.Width = width
            col.ReadOnly = readOnly
            col
        )

        fn setupGrid =
        (
            grid.AllowUserToAddRows = false
            grid.AllowUserToDeleteRows = false
            grid.RowHeadersVisible = false
            grid.MultiSelect = false
            grid.ReadOnly = true
            grid.SelectionMode = (dotNetClass "System.Windows.Forms.DataGridViewSelectionMode").FullRowSelect
            grid.AutoSizeRowsMode = (dotNetClass "System.Windows.Forms.DataGridViewAutoSizeRowsMode").AllCells
            grid.Columns.Clear()
            grid.Columns.Add (dnColText "nome" "Nome no site" 320)
            grid.Columns.Add (dnColText "categoria" "Categoria" 85)
            grid.Columns.Add (dnColText "marca" "Marca" 90)
            grid.Columns.Add (dnColText "dimensoes" "Dimensoes" 120)
            grid.Columns.Add (dnColText "acabamento" "Acabamento" 120)
            grid.Columns.Add (dnColText "valor" "Valor" 80)
            grid.Columns.Add (dnColText "valor_m2" "Valor/m2" 80)
            grid.Columns.Add (dnColText "fornecedor" "Fornecedor" 110)
        )

        fn selectedIdx =
        (
            local idx = 0
            try
            (
                if grid.SelectedRows.Count > 0 do idx = grid.SelectedRows.Item[0].Index + 1
            ) catch (idx = 0)
            idx
        )

        fn populateGrid =
        (
            grid.Rows.Clear()
            for it in G_TempSearchResults do
            (
                local rowIdx = grid.Rows.Add()
                local row = grid.Rows.Item[rowIdx]
                row.Cells.Item[0].Value = it[2]
                row.Cells.Item[1].Value = it[3]
                row.Cells.Item[2].Value = it[4]
                row.Cells.Item[3].Value = (it[5] as string) + " x " + (it[6] as string) + " x " + (it[7] as string) + " mm"
                row.Cells.Item[4].Value = it[8]
                row.Cells.Item[5].Value = "R$ " + (it[9] as string)
                row.Cells.Item[6].Value = "R$ " + (it[10] as string)
                row.Cells.Item[7].Value = it[11]
            )
        )

        fn updateDetail =
        (
            local idx = selectedIdx()
            if idx >= 1 and idx <= G_TempSearchResults.count then
            (
                local it = G_TempSearchResults[idx]
                lbDetail1.Text = "Produto: " + it[2]
                lbDetail2.Text = "Marca: " + it[4] + " | " + (it[5] as string) + "x" + (it[6] as string) + "x" + (it[7] as string) + "mm | Acab: " + it[8] + " | R$ " + (it[9] as string) + "/chapa | R$ " + (it[10] as string) + "/m2 | " + it[11]
                btnUsar.Enabled = true
            )
            else
            (
                lbDetail1.Text = ""
                lbDetail2.Text = ""
                btnUsar.Enabled = false
            )
        )

        fn updatePagButtons =
        (
            btnPrev.Enabled = (currentPage > 1)
            btnNext.Enabled = (G_TempSearchResults.count >= pageLimit)
            lbPag.Text = "Pag. " + (currentPage as string)
        )

        fn doSearch =
        (
            local termo = txtNome.Text
            local espMin = G_BuscaChapaEspMm - 0.5
            local espMax = G_BuscaChapaEspMm + 0.5
            local catNames = #("", "MDF", "MDP", "Compensado")
            local subcat = catNames[cmbCategoria.SelectedIndex + 1]

            lbStatus.Text = "Pesquisando..."
            btnUsar.Enabled = false
            lbDetail1.Text = ""
            lbDetail2.Text = ""
            grid.Rows.Clear()
            showLoading()

            G_TempSearchResults = apiSearchChapas termo espMin espMax subcategoria:subcat page:currentPage
            populateGrid()
            hideLoading()
            updatePagButtons()

            if G_TempSearchResults.count == 0 then
            (
                lbStatus.Text = "Nenhum resultado com preco disponivel."
            )
            else
            (
                local mostrou = G_TempSearchResults.count as string
                local totalBanco = G_LastSearchTotal as string
                lbStatus.Text = "Pag." + (currentPage as string) + "  |  " + mostrou + " resultados (total no banco: " + totalBanco + ")"
            )
        )

        fn usarSelecionado =
        (
            local idx = selectedIdx()
            if idx >= 1 and idx <= G_TempSearchResults.count do
            (
                local it = G_TempSearchResults[idx]
                local entry = #(G_BuscaChapaEspMm, it[9], it[2], it[8], it[5], it[6], it[10], it[11])
                local achou = false
                for i = 1 to G_ApiChapaPrecos.count do
                (
                    if abs(G_ApiChapaPrecos[i][1] - G_BuscaChapaEspMm) < 0.5 do
                    (
                        G_ApiChapaPrecos[i] = entry
                        achou = true
                        exit
                    )
                )
                if not achou do append G_ApiChapaPrecos entry
            )
            destroyDialog rlBuscaChapa
            try ( ::G_ActiveCustoRl.refreshFromApi() ) catch( try ( ::G_ActiveCustoRl.recalcular() ) catch() )
        )

        fn verDebug =
        (
            local tmpDir   = dirSep sysInfo.tempDir
            local dbgFile  = tmpDir + "cnc_api_debug.txt"
            local fIn = openFile dbgFile mode:"rt"
            if fIn == undefined do ( messageBox "Arquivo de debug nao encontrado ainda.\nFaca uma busca primeiro." title:"Debug"; return undefined )
            local conteudo = ""
            local n = 0
            while not eof fIn and n < 80 do ( conteudo += (readline fIn) + "\n"; n += 1 )
            close fIn
            if conteudo == "" do conteudo = "(vazio)"
            messageBox conteudo title:"Debug API (ultimas entradas)"
        )

        on rlBuscaChapa open do
        (
            lbInfo.Text      = "Espessura alvo: " + (G_BuscaChapaEspMm as string) + " mm"
            lbCategoria.Text = "Categoria"
            lbNome.Text      = "Produto"
            lbStatus.Text    = ""
            lbDetail1.Text   = ""
            lbDetail2.Text   = ""
            btnSearch.Text = "Pesquisar"
            btnUsar.Text   = "Usar este produto"
            btnCancel.Text = "← Voltar"
            btnDebug.Text  = "Ver Debug"
            btnPrev.Text   = "◄ Anterior"
            btnNext.Text   = "Próximo ►"
            lbPag.Text     = "Pag. 1"
            btnUsar.Enabled = false
            btnPrev.Enabled = false
            btnNext.Enabled = false
            lbLoad.Visible  = false
            currentPage = 1
            -- setupGrid DEVE vir antes de qualquer coisa que dispare SelectedIndexChanged
            -- (setar SelectedIndex = 0 abaixo aciona o evento e chama doSearch/populateGrid)
            setupGrid()
            try ( ::aplicarTemaForm lbInfo.FindForm() ) catch()

            cmbCategoria.DropDownStyle = (dotNetClass "System.Windows.Forms.ComboBoxStyle").DropDown
            for item in #("Todas", "MDF", "MDP", "Compensado") do cmbCategoria.Items.Add item
            suppressInitialSearch = true
            cmbCategoria.SelectedIndex = 0
            suppressInitialSearch = false
            try ( cmbCategoria.Text = cmbCategoria.Items.Item[cmbCategoria.SelectedIndex] ) catch()
            try ( cmbCategoria.BackColor = (dotNetClass "System.Drawing.Color").White ) catch()
            try ( cmbCategoria.ForeColor = (dotNetClass "System.Drawing.Color").FromArgb 27 32 38 ) catch()
            ::pintarBotaoPesquisar btnSearch
            ::pintarBotaoProximo btnUsar
            lbStatus.Text = "Clique em Pesquisar para carregar produtos desta espessura."
        )

        on btnSearch Click sender args do
        (
            currentPage = 1   -- nova busca começa sempre na página 1
            doSearch()
        )
        -- BUG-C-FIX: sempre refaz a busca ao mudar categoria
        on cmbCategoria SelectedIndexChanged sender args do
        (
            if not suppressInitialSearch do ( currentPage = 1; doSearch() )
        )
        on btnPrev Click sender args do
        (
            if currentPage > 1 do ( currentPage -= 1; doSearch() )
        )
        on btnNext Click sender args do
        (
            currentPage += 1
            doSearch()
        )
        on grid SelectionChanged sender args do updateDetail()
        on grid CellDoubleClick sender args do usarSelecionado()
        on btnUsar Click sender args do usarSelecionado()
        on btnCancel Click sender args do destroyDialog rlBuscaChapa
        on btnDebug Click sender args do verDebug()
        -- FIX TECLADO: sintaxe correta para dotNetControl em rollout (não dotNet.addEventHandler)
        on txtNome GotFocus  sender args do ( enableAccelerators = false )
        on txtNome LostFocus sender args do ( enableAccelerators = true  )
    )

    createDialog rlBuscaChapa style:#(#style_titlebar, #style_border, #style_sysmenu) bgcolor:(color 245 246 248)
)

-- ============================================================
-- FEATURE API: Modal de Busca de Fitas na API
-- ============================================================
fn abrirBuscaFitaAPI acabIdx acabamento =
(
    G_TempSearchResults = #()
    G_BuscaFitaAcabamento = acabamento

    rollout rlBuscaFita "Buscar Fita de Borda na API" width:760 height:536
    (
        dotNetControl lbInfo    "System.Windows.Forms.Label"       pos:[12,12]  width:720 height:18
        dotNetControl lbNome    "System.Windows.Forms.Label"       pos:[12,42]  width:90  height:18
        dotNetControl txtNome   "System.Windows.Forms.TextBox"     pos:[12,62]  width:570 height:24
        dotNetControl btnSearch "System.Windows.Forms.Button"      pos:[598,60] width:140 height:28
        -- Paginacao
        dotNetControl btnPrev   "System.Windows.Forms.Button"      pos:[12,96]  width:100 height:26
        dotNetControl lbPag     "System.Windows.Forms.Label"       pos:[120,102] width:70 height:16
        dotNetControl btnNext   "System.Windows.Forms.Button"      pos:[198,96] width:100 height:26
        -- Grid e detalhes (deslocados 32px para baixo)
        dotNetControl grid      "System.Windows.Forms.DataGridView" pos:[12,130] width:726 height:280
        dotNetControl lbStatus  "System.Windows.Forms.Label"       pos:[12,420] width:726 height:18
        dotNetControl lbDetail  "System.Windows.Forms.Label"       pos:[12,444] width:726 height:18
        dotNetControl btnUsar   "System.Windows.Forms.Button"      pos:[518,482] width:220 height:30
        dotNetControl btnCancel "System.Windows.Forms.Button"      pos:[12,482]  width:120 height:30
        dotNetControl lbLoad    "System.Windows.Forms.Label"       pos:[12,518]  width:726 height:16

        local currentPage = 1
        local pageLimit   = 20

        fn showLoading =
        (
            lbLoad.Text       = "|"
            lbLoad.Visible    = true
            btnSearch.Enabled = false
            G_ActiveSpinner   = lbLoad
            windows.processPostedMessages()
        )
        fn hideLoading =
        (
            G_ActiveSpinner   = undefined
            lbLoad.Visible    = false
            btnSearch.Enabled = true
        )

        fn dnColText name header width readOnly:true =
        (
            local col = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"
            col.Name = name
            col.HeaderText = header
            col.Width = width
            col.ReadOnly = readOnly
            col
        )

        fn setupGrid =
        (
            grid.AllowUserToAddRows = false
            grid.AllowUserToDeleteRows = false
            grid.RowHeadersVisible = false
            grid.MultiSelect = false
            grid.ReadOnly = true
            grid.SelectionMode = (dotNetClass "System.Windows.Forms.DataGridViewSelectionMode").FullRowSelect
            grid.AutoSizeRowsMode = (dotNetClass "System.Windows.Forms.DataGridViewAutoSizeRowsMode").AllCells
            grid.Columns.Clear()
            grid.Columns.Add (dnColText "nome" "Nome no site" 330)
            grid.Columns.Add (dnColText "marca" "Marca" 100)
            grid.Columns.Add (dnColText "rolo" "Rolo" 70)
            grid.Columns.Add (dnColText "valor_rolo" "Valor" 80)
            grid.Columns.Add (dnColText "valor_m" "Valor/m" 80)
            grid.Columns.Add (dnColText "fornecedor" "Fornecedor" 110)
        )

        fn selectedIdx =
        (
            local idx = 0
            try
            (
                if grid.SelectedRows.Count > 0 do idx = grid.SelectedRows.Item[0].Index + 1
            ) catch (idx = 0)
            idx
        )

        fn populateGrid =
        (
            grid.Rows.Clear()
            for it in G_TempSearchResults do
            (
                local rowIdx = grid.Rows.Add()
                local row = grid.Rows.Item[rowIdx]
                row.Cells.Item[0].Value = it[2]
                row.Cells.Item[1].Value = it[3]
                row.Cells.Item[2].Value = (it[4] as string) + " m"
                row.Cells.Item[3].Value = "R$ " + (it[5] as string)
                row.Cells.Item[4].Value = "R$ " + (it[6] as string)
                row.Cells.Item[5].Value = it[7]
            )
        )

        fn updateDetail =
        (
            local idx = selectedIdx()
            if idx >= 1 and idx <= G_TempSearchResults.count then
            (
                local it = G_TempSearchResults[idx]
                lbDetail.Text = it[3] + " | Rolo " + (it[4] as string) + "m | R$/rolo " + (it[5] as string) + " | R$/m " + (it[6] as string) + " | " + it[7]
                btnUsar.Enabled = true
            )
            else
            (
                lbDetail.Text = ""
                btnUsar.Enabled = false
            )
        )

        fn updatePagButtons =
        (
            btnPrev.Enabled = (currentPage > 1)
            btnNext.Enabled = (G_TempSearchResults.count >= pageLimit)
            lbPag.Text = "Pag. " + (currentPage as string)
        )

        fn doSearch =
        (
            local termo = txtNome.Text
            lbStatus.Text = "Pesquisando..."
            btnUsar.Enabled = false
            lbDetail.Text = ""
            grid.Rows.Clear()
            showLoading()
            G_TempSearchResults = apiSearchFitas termo page:currentPage
            populateGrid()
            hideLoading()
            updatePagButtons()

            if G_TempSearchResults.count == 0 then
            (
                lbStatus.Text = "Nenhuma fita com dados completos encontrada."
            )
            else
            (
                lbStatus.Text = "Pag." + (currentPage as string) + "  |  " + (G_TempSearchResults.count as string) + " fita(s) com rolo e preco/m"
            )
        )

        fn usarSelecionado =
        (
            local idx = selectedIdx()
            if idx >= 1 and idx <= G_TempSearchResults.count do
            (
                local it = G_TempSearchResults[idx]
                -- it = #(id, nome, marca, tamanho_rolo_m, valor_rolo, valor_m_linear, fornecedor)
                local entry = #(G_BuscaFitaAcabamento, it[6], it[2], it[4], it[5], it[7])
                -- Atualiza G_ApiFitaPrecos (compatibilidade retroativa)
                local achou = false
                for i = 1 to G_ApiFitaPrecos.count do
                (
                    if G_ApiFitaPrecos[i][1] == G_BuscaFitaAcabamento do
                    (
                        G_ApiFitaPrecos[i] = entry
                        achou = true
                        exit
                    )
                )
                if not achou do append G_ApiFitaPrecos entry
                -- Atualiza a linha alvo em G_FitasMultiLinhas
                -- formato: #(nome, metros, valor_m, rolo_m, fornecedor)
                local rowIdx = ::G_BuscaFitaTargetRow
                if rowIdx >= 1 and rowIdx <= ::G_FitasMultiLinhas.count then
                (
                    local metros = ::G_FitasMultiLinhas[rowIdx][2]  -- preserva metros
                    ::G_FitasMultiLinhas[rowIdx] = #(it[2], metros, it[6], it[4], it[7])
                )
                else
                (
                    -- rowIdx novo (append)
                    append ::G_FitasMultiLinhas #(it[2], 0.0, it[6], it[4], it[7])
                )
            )
            destroyDialog rlBuscaFita
            try ( ::G_ActiveCustoRl.refreshFromApi() ) catch( try ( ::G_ActiveCustoRl.recalcular() ) catch() )
        )

        on rlBuscaFita open do
        (
            lbInfo.Text    = "Acabamento: " + G_BuscaFitaAcabamento + " | Digite o nome da fita"
            lbNome.Text    = "Fita"
            lbStatus.Text  = ""
            lbDetail.Text  = ""
            btnSearch.Text = "Pesquisar"
            btnUsar.Text   = "Usar esta fita"
            btnCancel.Text = "← Voltar"
            btnPrev.Text   = "◄ Anterior"
            btnNext.Text   = "Próximo ►"
            lbPag.Text     = "Pag. 1"
            btnUsar.Enabled  = false
            btnPrev.Enabled  = false
            btnNext.Enabled  = false
            lbLoad.Visible   = false
            currentPage = 1
            setupGrid()
            try ( ::aplicarTemaForm lbInfo.FindForm() ) catch()
            ::pintarBotaoPesquisar btnSearch
            ::pintarBotaoProximo btnUsar
        )

        on txtNome GotFocus  sender args do ( enableAccelerators = false )
        on txtNome LostFocus sender args do ( enableAccelerators = true  )
        on btnSearch Click sender args do ( currentPage = 1; doSearch() )
        on btnPrev  Click sender args do ( if currentPage > 1 do ( currentPage -= 1; doSearch() ) )
        on btnNext  Click sender args do ( currentPage += 1; doSearch() )
        on grid SelectionChanged sender args do updateDetail()
        on grid CellDoubleClick sender args do usarSelecionado()
        on btnUsar Click sender args do usarSelecionado()
        on btnCancel Click sender args do destroyDialog rlBuscaFita
    )

    createDialog rlBuscaFita style:#(#style_titlebar, #style_border, #style_sysmenu) bgcolor:(color 245 246 248)
)

-- ============================================================
-- FEATURE API: Modal de Busca de Ferragens na API
-- ============================================================
fn abrirBuscaFerragemAPI =
(
    G_TempSearchResults = #()

    rollout rlBuscaFerragem "Buscar Ferragem na API" width:760 height:556
    (
        dotNetControl lbTitulo    "System.Windows.Forms.Label"        pos:[12,12]  width:600 height:18
        dotNetControl lbNome      "System.Windows.Forms.Label"        pos:[12,38]  width:60  height:18
        dotNetControl txtNome     "System.Windows.Forms.TextBox"      pos:[76,36]  width:400 height:24
        dotNetControl btnSearch   "System.Windows.Forms.Button"       pos:[486,34] width:140 height:28
        dotNetControl lbQtdLabel  "System.Windows.Forms.Label"        pos:[636,38] width:28  height:18
        dotNetControl txtQtd      "System.Windows.Forms.TextBox"      pos:[668,36] width:80  height:24
        -- Paginacao
        dotNetControl btnPrev     "System.Windows.Forms.Button"       pos:[12,68]  width:100 height:26
        dotNetControl lbPag       "System.Windows.Forms.Label"        pos:[120,74] width:70  height:16
        dotNetControl btnNext     "System.Windows.Forms.Button"       pos:[198,68] width:100 height:26
        -- Grid e controles deslocados 32px abaixo do original
        dotNetControl grid        "System.Windows.Forms.DataGridView" pos:[12,100] width:726 height:296
        dotNetControl lbStatus    "System.Windows.Forms.Label"        pos:[12,404] width:726 height:18
        dotNetControl lbDetail    "System.Windows.Forms.Label"        pos:[12,426] width:726 height:34
        dotNetControl btnAdicionar "System.Windows.Forms.Button"      pos:[12,472]  width:260 height:34
        dotNetControl lbSelecionados "System.Windows.Forms.Label"     pos:[284,478] width:348 height:22
        dotNetControl btnFechar   "System.Windows.Forms.Button"       pos:[632,472] width:118 height:34
        dotNetControl lbLoad      "System.Windows.Forms.Label"        pos:[12,514] width:726 height:16

        local currentPage = 1
        local pageLimit   = 20

        fn showLoading =
        (
            lbLoad.Text = "|"
            lbLoad.Visible = true
            btnSearch.Enabled = false
            G_ActiveSpinner = lbLoad
            windows.processPostedMessages()
        )
        fn hideLoading =
        (
            G_ActiveSpinner = undefined
            lbLoad.Visible = false
            btnSearch.Enabled = true
        )

        fn setupGrid =
        (
            grid.AllowUserToAddRows    = false
            grid.AllowUserToDeleteRows = false
            grid.RowHeadersVisible     = false
            grid.MultiSelect           = false
            grid.ReadOnly              = true
            grid.SelectionMode = (dotNetClass "System.Windows.Forms.DataGridViewSelectionMode").FullRowSelect
            grid.AutoSizeRowsMode = (dotNetClass "System.Windows.Forms.DataGridViewAutoSizeRowsMode").AllCells
            grid.Columns.Clear()
            local col1 = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"
            col1.Name = "nome";       col1.HeaderText = "Nome";        col1.Width = 270; col1.ReadOnly = true
            local col2 = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"
            col2.Name = "marca";      col2.HeaderText = "Marca";       col2.Width = 120; col2.ReadOnly = true
            local col3 = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"
            col3.Name = "valor";      col3.HeaderText = "Valor Unit."; col3.Width =  90; col3.ReadOnly = true
            local col4 = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"
            col4.Name = "fornecedor"; col4.HeaderText = "Fornecedor";  col4.Width = 220; col4.ReadOnly = true
            grid.Columns.Add col1
            grid.Columns.Add col2
            grid.Columns.Add col3
            grid.Columns.Add col4
        )

        fn selectedIdx =
        (
            local idx = 0
            try ( if grid.SelectedRows.Count > 0 do idx = grid.SelectedRows.Item[0].Index + 1 ) catch (idx = 0)
            idx
        )

        fn populateGrid =
        (
            grid.Rows.Clear()
            for it in ::G_TempSearchResults do
            (
                local ri = grid.Rows.Add()
                local rw = grid.Rows.Item[ri]
                rw.Cells.Item[0].Value = it[2]
                rw.Cells.Item[1].Value = it[3]
                rw.Cells.Item[2].Value = "R$ " + (it[4] as string)
                rw.Cells.Item[3].Value = it[5]
            )
        )

        fn atualizarResumoSelecionados =
        (
            local total = 0.0
            local count = 0
            for fe in ::G_FerragensLista do
            (
                total += fe[3] * fe[5]
                count += fe[5]
            )
            if count > 0 then
                lbSelecionados.Text = (::G_FerragensLista.count as string) + " tipo(s)  |  Total: R$ " + \
                    (((floor (total * 100.0 + 0.5)) / 100.0) as string)
            else
                lbSelecionados.Text = ""
        )

        fn updateDetail =
        (
            local idx = selectedIdx()
            if idx >= 1 and idx <= ::G_TempSearchResults.count then
            (
                local it = ::G_TempSearchResults[idx]
                lbDetail.Text = it[2] + "  |  Marca: " + it[3] + "  |  R$ " + (it[4] as string) + "  |  " + it[5]
                btnAdicionar.Enabled = true
            )
            else
            (
                lbDetail.Text = ""
                btnAdicionar.Enabled = false
            )
        )

        fn updatePagButtons =
        (
            btnPrev.Enabled = (currentPage > 1)
            btnNext.Enabled = (::G_TempSearchResults.count >= pageLimit)
            lbPag.Text = "Pag. " + (currentPage as string)
        )

        fn doSearch =
        (
            lbStatus.Text = "Pesquisando..."
            btnAdicionar.Enabled = false
            lbDetail.Text = ""
            grid.Rows.Clear()
            showLoading()
            ::G_TempSearchResults = ::apiSearchFerragens txtNome.Text page:currentPage
            populateGrid()
            hideLoading()
            updatePagButtons()
            if ::G_TempSearchResults.count == 0 then
                lbStatus.Text = "Nenhuma ferragem encontrada."
            else
                lbStatus.Text = "Pag." + (currentPage as string) + "  |  " + \
                    (::G_TempSearchResults.count as string) + " ferragem(ns)   (Total no banco: " + (::G_LastSearchTotal as string) + ")"
        )

        fn adicionarSelecionado =
        (
            local idx = selectedIdx()
            if idx < 1 or idx > ::G_TempSearchResults.count do return undefined
            local it = ::G_TempSearchResults[idx]
            local qtd = 1
            try ( qtd = txtQtd.Text as integer ) catch ( qtd = 1 )
            if qtd < 1 do qtd = 1
            -- Verifica se ja existe na lista pelo id — se sim, soma qtd
            local ferragemId = it[1]
            local achou = false
            for i = 1 to ::G_FerragensLista.count do
            (
                if ::G_FerragensLista[i][1] == ferragemId do
                (
                    ::G_FerragensLista[i][5] = ::G_FerragensLista[i][5] + qtd
                    achou = true; exit
                )
            )
            if not achou do append ::G_FerragensLista #(it[1], it[2], it[4], it[5], qtd)
            -- #(id, nome, valor, fornecedor, qtd)
            atualizarResumoSelecionados()
            lbStatus.Text = "Adicionado: " + it[2] + "  x" + (qtd as string)
            try ( ::G_ActiveCustoRl.refreshFerragensInfo() ) catch()
        )

        on rlBuscaFerragem open do
        (
            lbTitulo.Text       = "Pesquisar ferragem no banco de dados"
            lbNome.Text         = "Nome"
            lbQtdLabel.Text     = "Qtd"
            txtQtd.Text         = "1"
            lbStatus.Text       = "Digite o nome da ferragem e clique em Pesquisar."
            lbDetail.Text       = ""
            lbSelecionados.Text = ""
            btnSearch.Text      = "Pesquisar"
            btnAdicionar.Text   = "Adicionar a Cotacao"
            btnFechar.Text      = "Fechar"
            btnPrev.Text        = "◄ Anterior"
            btnNext.Text        = "Próximo ►"
            lbPag.Text          = "Pag. 1"
            btnAdicionar.Enabled = false
            btnPrev.Enabled      = false
            btnNext.Enabled      = false
            lbLoad.Visible       = false
            currentPage = 1
            setupGrid()
            try ( ::aplicarTemaForm lbTitulo.FindForm() ) catch()
            ::pintarBotaoPesquisar btnSearch
            atualizarResumoSelecionados()
        )

        on txtNome GotFocus  sender args do ( enableAccelerators = false )
        on txtNome LostFocus sender args do ( enableAccelerators = true  )
        on txtQtd  GotFocus  sender args do ( enableAccelerators = false )
        on txtQtd  LostFocus sender args do ( enableAccelerators = true  )
        on btnSearch    Click sender args do ( currentPage = 1; doSearch() )
        on btnPrev      Click sender args do ( if currentPage > 1 do ( currentPage -= 1; doSearch() ) )
        on btnNext      Click sender args do ( currentPage += 1; doSearch() )
        on grid SelectionChanged sender args do updateDetail()
        on grid CellDoubleClick  sender args do adicionarSelecionado()
        on btnAdicionar Click sender args do adicionarSelecionado()
        on btnFechar    Click sender args do destroyDialog rlBuscaFerragem
        on rlBuscaFerragem close do
        (
            -- Notifica o caller (modeless): permite recarregar grids dependentes
            try ( if ::G_FerragemDialogOnClose != undefined do ::G_FerragemDialogOnClose() ) catch()
            ::G_FerragemDialogOnClose = undefined
        )
    )

    createDialog rlBuscaFerragem style:#(#style_titlebar, #style_border, #style_sysmenu) bgcolor:(color 245 246 248)
)

-- ============================================================
-- FEATURE CUSTO: UI de planejamento de custos
-- Usa execute(stringStream) para evitar limitaÃ§Ãµes de closure do MAXScript
-- ============================================================
-- ============================================================
-- PLANILHA DE CUSTOS: escrita do arquivo e chamada Python
-- ============================================================
fn gerarPlanilhaExcel precos wastePct priceMetroFita priceFerragem priceCola priceMaoObra priceFrete cotacaoId:0 custoAquisicaoGeral:0.0 custoProdutoGeral:0.0 pecasJsonStr:"[]" moManual:false margemPct:0.0 impostoPct:0.0 comissaoPct:0.0 precoVenda:0.0 precoVendaFinal:0.0 custoFitaTotal:0.0 custoFitaAquisicao:0.0 cobTotal:0.0 =
(
    local pyScript = (dirSep G_ScriptDir) + "cnc_planilha.py"
    local tmpDir   = dirSep sysInfo.tempDir
    local dataFile = tmpDir + "cnc_planilha_data.txt"

    local savePath = getSaveFileName caption:"Salvar Planilha de Custos" types:"Excel (*.xlsx)|*.xlsx|"
    if savePath == undefined do return undefined

    local fOut = openFile dataFile mode:"wt"
    if fOut == undefined do ( messageBox "Erro ao criar arquivo de dados." title:"Erro Planilha"; return undefined )

    format "output=%\n"          savePath          to:fOut
    format "waste_pct=%\n"       wastePct          to:fOut
    format "fita_total_m=%\n"    G_TotalFitaMetros to:fOut
    format "price_fita_m=%\n"    priceMetroFita    to:fOut
    format "price_ferragem=%\n"  priceFerragem     to:fOut
    format "price_cola=%\n"      priceCola         to:fOut
    format "price_mao_obra=%\n"  priceMaoObra      to:fOut
    format "price_frete=%\n"     priceFrete        to:fOut
    format "cotacao_id=%\n"            cotacaoId            to:fOut
    format "custo_aquisicao_geral=%\n" custoAquisicaoGeral  to:fOut
    format "custo_produto_geral=%\n"   custoProdutoGeral    to:fOut
    format "mo_manual=%\n"             (if moManual then "true" else "false") to:fOut
    format "aproveitamento_pct=%\n"    G_CustoAprovArred    to:fOut
    -- Modelo de precificacao v10: margem por divisor + imposto + comissao
    format "margem_pct=%\n"            margemPct            to:fOut
    format "imposto_pct=%\n"           impostoPct           to:fOut
    format "comissao_pct=%\n"          comissaoPct          to:fOut
    format "preco_venda=%\n"           precoVenda           to:fOut
    format "preco_venda_final=%\n"     precoVendaFinal      to:fOut
    format "custo_fita_total=%\n"      custoFitaTotal       to:fOut
    format "custo_fita_aquisicao=%\n"  custoFitaAquisicao   to:fOut
    format "custo_operacional=%\n"     cobTotal             to:fOut

    -- Feature 1: dados do projeto/cliente
    local nomeProjeto = if G_DadosCotacaoCliente.count >= 2 then G_DadosCotacaoCliente[2] else ""
    local obsGeral    = if G_DadosCotacaoCliente.count >= 3 then G_DadosCotacaoCliente[3] else ""
    local previsao    = if G_DadosCotacaoCliente.count >= 4 then G_DadosCotacaoCliente[4] else ""
    local descGlobal  = if G_DadosCotacaoCliente.count >= 5 then G_DadosCotacaoCliente[5] else 0.0
    local cliId       = if G_DadosCotacaoCliente.count >= 1 then G_DadosCotacaoCliente[1] else 0

    format "nome_projeto=%\n"       nomeProjeto  to:fOut
    format "obs_geral=%\n"          obsGeral     to:fOut
    format "previsao_entrega=%\n"   previsao     to:fOut
    format "desconto_global=%\n"    descGlobal   to:fOut

    -- Busca dados do cliente na API (se disponivel)
    local cliNome = ""; local cliDoc = ""; local cliTel = ""; local cliEmail = ""; local cliCid = ""; local cliUF = ""
    if cliId > 0 and G_ApiOnline do
    (
        local cli = ::apiGetCliente cliId
        if cli.count >= 6 do
        (
            cliNome  = cli[1]; cliDoc  = cli[2]; cliTel   = cli[3]
            cliEmail = cli[4]; cliCid  = cli[5]; cliUF    = cli[6]
        )
    )
    format "cliente_id=%\n"         cliId        to:fOut
    format "cliente_nome=%\n"       cliNome      to:fOut
    format "cliente_documento=%\n"  cliDoc       to:fOut
    format "cliente_telefone=%\n"   cliTel       to:fOut
    format "cliente_email=%\n"      cliEmail     to:fOut
    format "cliente_cidade=%\n"     cliCid       to:fOut
    format "cliente_uf=%\n"         cliUF        to:fOut

    -- Chapas por espessura (inclui nome do produto selecionado via API)
    format "chapas_count=%\n" G_ChapasGrupos.count to:fOut
    for i = 1 to G_ChapasGrupos.count do
    (
        local espMm   = G_ChapasGrupos[i][1]
        local qtd     = G_ChapasGrupos[i][2]
        local preco   = precos[i]
        local wMm     = 1830.0; local hMm = 2750.0
        local prodNome = "Manual"
        local acabProd = ""
        for c in G_PdfChapas do
            if abs(c[2] - espMm) < 0.1 do ( wMm = c[3]; hMm = c[4]; exit )
        for en in G_ApiChapaPrecos do
            if abs(en[1] - espMm) < 0.5 do ( prodNome = en[3]; acabProd = en[4]; exit )
        format "chapa,%,%,%,%,%,%,%\n" espMm qtd preco wMm hMm prodNome acabProd to:fOut
    )

    -- Fita selecionada via API (se existir)
    local fitaNome = "Manual"; local fitaRoloM = 50
    if G_ApiFitaPrecos.count > 0 do
    (
        fitaNome  = G_ApiFitaPrecos[1][3]
        fitaRoloM = G_ApiFitaPrecos[1][4] as integer
    )
    format "fita_nome=%\n"   fitaNome  to:fOut
    format "fita_rolo_m=%\n" fitaRoloM to:fOut

    -- Pecas individuais com fita
    format "pecas_count=%\n" G_PiecesData.count to:fOut
    for p in G_PiecesData do
    (
        local espMm = (floor (p.esp * 25.4 * 10 + 0.5)) / 10.0
        local cMm   = (floor (p.comp * 25.4 * 10 + 0.5)) / 10.0
        local lMm   = (floor (p.larg * 25.4 * 10 + 0.5)) / 10.0
        local fitaM = 0.0
        if p.c1 do fitaM += cMm / 1000.0
        if p.c2 do fitaM += cMm / 1000.0
        if p.l1 do fitaM += lMm / 1000.0
        if p.l2 do fitaM += lMm / 1000.0
        format "peca,%,%,%,%,%\n" p.nome cMm lMm espMm fitaM to:fOut
    )
    -- Pecas do projeto (JSON para aba dedicada na planilha) — passado pelo chamador
    local pecasJsonSafe = if pecasJsonStr == "" then "[]" else pecasJsonStr
    format "pecas_plano_json=%\n" pecasJsonSafe to:fOut
    close fOut

    python.ExecuteFile pyScript
    local err = python.GetLastError()
    if err != "" then
        messageBox ("Erro ao gerar planilha:\n" + err) title:"Erro Planilha"
    else
        messageBox ("Planilha gerada com sucesso!\n\n" + savePath) title:"Planilha OK"
)

-- ============================================================
-- UI UNIFICADA: Custo + Planilha em uma Ãºnica janela
-- Integrada com API Banco de Dados para busca de precos
-- ============================================================
fn abrirUICustoCompleto nChapas aproveitamento fitaMetros =
(
    local fitaArred = (floor (fitaMetros * 10 + 0.5)) / 10.0
    local aprovArred= (floor (aproveitamento * 10 + 0.5)) / 10.0
    local nEsp      = G_ChapasGrupos.count
    local nPecas    = G_PiecesData.count
    local despEst   = calcEstimativaDesperdicio nPecas nEsp aproveitamento

    -- Limpa selecoes anteriores da API
    G_ApiChapaPrecos = #()
    G_ApiFitaPrecos  = #()

    global G_CustoNChapas = nChapas
    global G_CustoAprovArred = aprovArred
    global G_CustoFitaArred = fitaArred
    global G_CustoFitaMetros = fitaMetros
    global G_CustoDespEst = despEst

    rollout rlCusto "Planejamento de Custo e Cotacao" width:980 height:950
    (
        dotNetControl pnl "System.Windows.Forms.Panel" pos:[8,8] width:964 height:888
        dotNetControl btnCriarCot   "System.Windows.Forms.Button" pos:[718,902] width:254 height:34
        dotNetControl btnClose      "System.Windows.Forms.Button" pos:[8,902]   width:120 height:34
        dotNetControl btnCotacoes   "System.Windows.Forms.Button" pos:[136,902] width:174 height:34
        dotNetControl lbFooter      "System.Windows.Forms.Label"  pos:[318,911] width:388 height:18
        dotNetControl lbLoad        "System.Windows.Forms.Label"  pos:[318,894] width:388 height:16

        local gridChapas, gridFitas
        local txtDesp, txtFerr, txtCola, txtFrete, txtMargemLucro, txtImposto, txtComissao
        local txtMOManual, chkMOManual, lbMOEstimada
        local lbRch, lbRft, lbRou, lbRfr, lbRmo, lbTot, lbEfetivo, lbProduto, lbMO
        local lbCMC, lbCOB
        local lbFerragensInfo
        local btnBuscarChapa, btnAtualizar, btnBuscarFita
        local btnAdicionarFita, btnRemoverFita, btnBuscarFerragem
        local suppressEvents = false

        fn dnPoint x y = dotNetObject "System.Drawing.Point" x y
        fn dnSize w h = dotNetObject "System.Drawing.Size" w h

        fn addLabel parent text x y w h =
        (
            local c = dotNetObject "System.Windows.Forms.Label"
            c.Text = text
            c.Location = dnPoint x y
            c.Size = dnSize w h
            parent.Controls.Add c
            c
        )

        fn addText parent text x y w h =
        (
            local c = dotNetObject "System.Windows.Forms.TextBox"
            c.Text = text
            c.Location = dnPoint x y
            c.Size = dnSize w h
            parent.Controls.Add c
            c
        )

        fn addButton parent text x y w h =
        (
            local c = dotNetObject "System.Windows.Forms.Button"
            c.Text = text
            c.Location = dnPoint x y
            c.Size = dnSize w h
            parent.Controls.Add c
            c
        )

        fn addGroup parent text x y w h =
        (
            local c = dotNetObject "System.Windows.Forms.GroupBox"
            c.Text = text
            c.Location = dnPoint x y
            c.Size = dnSize w h
            parent.Controls.Add c
            c
        )

        fn dnColText name header width readOnly:true =
        (
            local col = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"
            col.Name = name
            col.HeaderText = header
            col.Width = width
            col.ReadOnly = readOnly
            col
        )

        fn parseFloatText value defaultVal =
        (
            local raw = if value == undefined then "" else (value as string)
            raw = substituteString raw "," "."
            raw = substituteString raw "R$" ""
            raw = substituteString raw " " ""
            local v = defaultVal
            try (v = raw as float) catch (v = defaultVal)
            v
        )

        fn money v = (((floor(v * 100.0 + 0.5)) / 100.0) as string)

        fn getChapaEntry espMm =
        (
            local found = undefined
            for en in G_ApiChapaPrecos do
                if found == undefined and abs(en[1] - espMm) < 0.5 do found = en
            found
        )

        fn selectedChapaRow =
        (
            local idx = 0
            try
            (
                if gridChapas.SelectedRows.Count > 0 do idx = gridChapas.SelectedRows.Item[0].Index + 1
            ) catch (idx = 0)
            idx
        )

        fn setupGrid =
        (
            gridChapas.AllowUserToAddRows = false
            gridChapas.AllowUserToDeleteRows = false
            gridChapas.RowHeadersVisible = false
            gridChapas.MultiSelect = false
            gridChapas.SelectionMode = (dotNetClass "System.Windows.Forms.DataGridViewSelectionMode").FullRowSelect
            gridChapas.AutoSizeRowsMode = (dotNetClass "System.Windows.Forms.DataGridViewAutoSizeRowsMode").AllCells
            gridChapas.Columns.Clear()
            gridChapas.Columns.Add (dnColText "esp" "Esp. mm" 70)
            gridChapas.Columns.Add (dnColText "qtd" "Qtd" 50)
            gridChapas.Columns.Add (dnColText "produto" "Produto selecionado" 360)
            gridChapas.Columns.Add (dnColText "fornecedor" "Fornecedor" 110)
            gridChapas.Columns.Add (dnColText "valor" "Valor R$/chapa" 110 readOnly:false)
            gridChapas.Columns.Add (dnColText "valor_m2" "Valor/m2" 90)
        )

        fn refreshChapasGrid =
        (
            if gridChapas == undefined do return undefined
            local oldValues = #()
            try
            (
                for r = 0 to gridChapas.Rows.Count - 1 do
                (
                    local oldEsp = parseFloatText gridChapas.Rows.Item[r].Cells.Item[0].Value -999.0
                    local oldVal = gridChapas.Rows.Item[r].Cells.Item[4].Value
                    append oldValues #(oldEsp, oldVal)
                )
            ) catch()

            suppressEvents = true
            gridChapas.Rows.Clear()
            for i = 1 to G_ChapasGrupos.count do
            (
                local espMm = G_ChapasGrupos[i][1]
                local qtd = G_ChapasGrupos[i][2]
                local entry = getChapaEntry espMm
                local produto = "Manual"
                local fornecedor = ""
                local valor = "0.0"
                local valorM2 = ""
                if entry != undefined do
                (
                    produto = entry[3]
                    fornecedor = if entry.count >= 8 then entry[8] else ""
                    valor = entry[2] as string
                    valorM2 = if entry.count >= 7 then entry[7] as string else ""
                )
                if entry == undefined do
                (
                    for ov in oldValues do
                        if abs(ov[1] - espMm) < 0.5 do valor = ov[2] as string
                )
                local rowIdx = gridChapas.Rows.Add()
                local row = gridChapas.Rows.Item[rowIdx]
                row.Cells.Item[0].Value = espMm as string
                row.Cells.Item[1].Value = qtd as string
                row.Cells.Item[2].Value = produto
                row.Cells.Item[3].Value = fornecedor
                row.Cells.Item[4].Value = valor
                row.Cells.Item[5].Value = valorM2
            )
            if gridChapas.Rows.Count > 0 do gridChapas.Rows.Item[0].Selected = true
            suppressEvents = false
        )

        fn refreshFitasGrid =
        (
            if gridFitas == undefined do return undefined
            suppressEvents = true
            gridFitas.Rows.Clear()
            for ft in ::G_FitasMultiLinhas do
            (
                local ri = gridFitas.Rows.Add()
                local rw = gridFitas.Rows.Item[ri]
                rw.Cells.Item[0].Value = ft[1]
                rw.Cells.Item[1].Value = ft[2] as string
                rw.Cells.Item[2].Value = ft[3] as string
                local sub = (try (ft[2] as float) catch 0.0) * (try (ft[3] as float) catch 0.0)
                rw.Cells.Item[3].Value = "R$ " + (money sub)
            )
            suppressEvents = false
        )

        fn refreshFerragensInfo =
        (
            local totalFerr = 0.0
            for fe in ::G_FerragensLista do
                totalFerr += (try (fe[3] as float) catch 0.0) * (try (fe[5] as integer) catch 1)
            if txtFerr != undefined do txtFerr.Text = money totalFerr
            if lbFerragensInfo != undefined do
            (
                if ::G_FerragensLista.count == 0 then
                    lbFerragensInfo.Text = "Nenhuma ferragem selecionada"
                else
                (
                    local info = ""
                    for fe in ::G_FerragensLista do
                    (
                        local sub = (try (fe[3] as float) catch 0.0) * (try (fe[5] as integer) catch 1)
                        info += fe[2] + " x" + (fe[5] as string) + " = R$" + (money sub) + "  "
                    )
                    lbFerragensInfo.Text = info
                )
            )
        )

        fn readGridPrice i =
        (
            local row = gridChapas.Rows.Item[i-1]
            parseFloatText row.Cells.Item[4].Value 0.0
        )

        fn recalcular =
        (
            if suppressEvents do return undefined

            local desp   = parseFloatText txtDesp.Text   0.0
            local ferr   = parseFloatText txtFerr.Text   0.0
            local cola   = parseFloatText txtCola.Text   0.0
            local frete  = parseFloatText txtFrete.Text  0.0
            local margem   = try (parseFloatText txtMargemLucro.Text 30.0) catch 30.0
            local imposto  = try (parseFloatText txtImposto.Text  0.0) catch 0.0
            local comissao = try (parseFloatText txtComissao.Text 0.0) catch 0.0

            -- MO: auto ou override manual
            local moEstimado = try (::calcularMaoObra()) catch 0.0
            local moManual   = try (chkMOManual.Checked) catch false
            local maoObra    = if moManual then (parseFloatText txtMOManual.Text 0.0) else moEstimado
            suppressEvents = true
            try ( lbMOEstimada.Text = "Auto: R$ " + money moEstimado ) catch()
            try ( txtMOManual.Enabled = moManual ) catch()
            suppressEvents = false

            -- ── CA_Chapas: aquisicao real = chapas inteiras consumidas pelo plano
            -- (a sobra ja esta paga dentro da chapa inteira; sem multiplicador de desperdicio)
            local caChapas = 0.0
            for i = 1 to G_ChapasGrupos.count do
            (
                local qtd   = G_ChapasGrupos[i][2]
                local preco = readGridPrice i
                caChapas += qtd * preco
            )

            -- ── CMC_Fitas: metros consumidos × preco/m ──
            local cmcFitas = 0.0
            for ft in ::G_FitasMultiLinhas do
            (
                local metros = try (ft[2] as float) catch 0.0
                local valM   = try (ft[3] as float) catch 0.0
                cmcFitas += metros * valM
            )

            -- ── CA_Fitas: aquisicao por rolo fechado (compra-se rolo inteiro) ──
            local caFitas = 0.0
            for ft in ::G_FitasMultiLinhas do
            (
                local metros = try (ft[2] as float) catch 0.0
                local valM   = try (ft[3] as float) catch 0.0
                local roloM  = try (ft[4] as float) catch 50.0
                if roloM <= 0.0 do roloM = 50.0
                local nRolos = ceil (metros / roloM)
                if metros > 0.0 and nRolos < 1.0 do nRolos = 1.0
                caFitas += nRolos * roloM * valM
            )

            -- ── CMC_Chapas: area das pecas × preco/m2 × (1 + perda real do plano) ──
            -- Perda derivada do aproveitamento real do MAXRECTS; fallback k_perda do INI
            local aprovReal = try (::G_CustoAprovArred as float) catch 0.0
            local kPerda    = if aprovReal > 1.0 then (100.0 / aprovReal - 1.0) \
                              else (try (::G_MO_KPerdaSeguranca as float) catch 0.10)
            if kPerda < 0.0 do kPerda = 0.0
            if kPerda > 1.0 do kPerda = 1.0
            local cmcChapas = 0.0
            for p in G_PiecesData do
            (
                local espMm  = (floor (p.esp  * 25.4 * 10 + 0.5)) / 10.0
                local areaM2 = (p.comp * 25.4 / 1000.0) * (p.larg * 25.4 / 1000.0)
                local valM2  = 0.0
                for en in ::G_ApiChapaPrecos do
                    if abs(en[1] - espMm) < 0.5 do ( valM2 = try (en[7] as float) catch 0.0; exit )
                cmcChapas += areaM2 * valM2
            )
            cmcChapas *= (1.0 + kPerda)

            -- ── Ferragens ──
            local totalFerr = 0.0
            for fe in ::G_FerragensLista do
                totalFerr += (try (fe[3] as float) catch 0.0) * (try (fe[5] as integer) catch 1)

            -- ── Totais: PV por markup divisor (margem + imposto + comissao por dentro) ──
            local cmc  = cmcChapas + cmcFitas
            local cob  = cmc + totalFerr + cola + frete + maoObra
            local somaPct = margem + imposto + comissao
            if somaPct > 95.0 do somaPct = 95.0
            local pv   = cob / (1.0 - somaPct / 100.0)
            -- CA = aquisicao total (chapas inteiras + rolos fechados de fita, sem MO)
            local caTotal = caChapas + caFitas + totalFerr + cola + frete

            -- ── Atualiza labels ──
            try ( lbRch.Text  = "CA Chapas (inteiras consumidas): R$ " + money caChapas ) catch()
            try ( lbRft.Text  = "Fitas consumo: R$ " + (money cmcFitas) + "  |  aquisicao (rolos): R$ " + (money caFitas) ) catch()
            try ( lbRou.Text  = "Ferragens: R$ " + money totalFerr ) catch()
            try ( lbRfr.Text  = "Cola + Frete: R$ " + money (cola + frete) ) catch()
            try ( lbRmo.Text  = "Mao de Obra: R$ " + money maoObra ) catch()
            local kPerdaPct   = (floor (kPerda * 100 + 0.5)) as integer
            local margemInt   = (floor (margem   + 0.5)) as integer
            local impostoInt  = (floor (imposto  + 0.5)) as integer
            local comissaoInt = (floor (comissao + 0.5)) as integer
            try ( lbCMC.Text  = "CMC (mat. consumido c/ " + (kPerdaPct as string) + "% perda real): R$ " + money cmc ) catch()
            try ( lbCOB.Text  = "COB (custo operacional base): R$ " + money cob ) catch()
            try ( lbMO.Text   = "Margem " + (margemInt as string) + "% + Imposto " + (impostoInt as string) + "% + Comissao " + (comissaoInt as string) + "% (por dentro do preco)" ) catch()
            try ( lbTot.Text  = "PRECO DE VENDA: R$ " + money pv ) catch()
            try ( lbEfetivo.Text = "CA Total (aquisicao s/ MO): R$ " + money caTotal ) catch()
            try ( lbProduto.Text = "Lucro estimado: R$ " + money (pv * margem / 100.0) ) catch()
        )

        fn refreshFromApi =
        (
            refreshChapasGrid()
            -- Se G_FitasMultiLinhas ainda vazio, inicializa com produto da API (se disponivel)
            if ::G_FitasMultiLinhas.count == 0 do
            (
                if G_ApiFitaPrecos.count > 0 then
                (
                    local ft = G_ApiFitaPrecos[1]
                    local forn = if ft.count >= 6 then ft[6] else ""
                    ::G_FitasMultiLinhas = #(#(ft[3], G_CustoFitaMetros, ft[2], ft[4], forn))
                )
                else
                (
                    ::G_FitasMultiLinhas = #(#("(Selecionar na API)", G_CustoFitaMetros, 0.0, 50.0, ""))
                )
            )
            refreshFitasGrid()
            refreshFerragensInfo()
            recalcular()
        )

        fn onBuscarChapa sender args =
        (
            if not G_ApiOnline do
            (
                messageBox "API offline. Use valor manual ou inicie a API." title:"API Offline"
                return undefined
            )
            local idx = selectedChapaRow()
            if idx < 1 or idx > G_ChapasGrupos.count then
                messageBox "Selecione uma linha de chapa na grade." title:"Selecionar Chapa"
            else
                ::abrirBuscaChapaAPI idx G_ChapasGrupos[idx][1]
        )

        fn onBuscarFita sender args =
        (
            if not G_ApiOnline do
            (
                messageBox "API offline. Use valor manual ou inicie a API." title:"API Offline"
                return undefined
            )
            -- Determina qual linha de fita esta selecionada no gridFitas
            local rowIdx = 1
            try ( if gridFitas.SelectedRows.Count > 0 do rowIdx = gridFitas.SelectedRows.Item[0].Index + 1 ) catch()
            if rowIdx < 1 do rowIdx = 1
            ::G_BuscaFitaTargetRow = rowIdx
            local acab = "Geral"
            if G_ApiChapaPrecos.count > 0 do acab = G_ApiChapaPrecos[1][4]
            ::abrirBuscaFitaAPI rowIdx acab
        )

        fn onAdicionarFita sender args =
        (
            -- Adiciona nova linha de fita com 0 metros (usuario define depois)
            append ::G_FitasMultiLinhas #("(Selecionar na API)", 0.0, 0.0, 50.0, "")
            refreshFitasGrid()
            if gridFitas != undefined and gridFitas.Rows.Count > 0 do
                try ( gridFitas.Rows.Item[gridFitas.Rows.Count - 1].Selected = true ) catch()
            recalcular()
        )

        fn onRemoverFita sender args =
        (
            if ::G_FitasMultiLinhas.count <= 1 do
            (
                messageBox "Mantenha pelo menos uma fita." title:"Aviso"
                return undefined
            )
            local rowIdx = 1
            try ( if gridFitas.SelectedRows.Count > 0 do rowIdx = gridFitas.SelectedRows.Item[0].Index + 1 ) catch()
            if rowIdx < 1 or rowIdx > ::G_FitasMultiLinhas.count do return undefined
            local novaLista = #()
            for i = 1 to ::G_FitasMultiLinhas.count do
                if i != rowIdx do append novaLista ::G_FitasMultiLinhas[i]
            ::G_FitasMultiLinhas = novaLista
            refreshFitasGrid()
            recalcular()
        )

        fn onFitasGridChanged sender args =
        (
            if suppressEvents do return undefined
            suppressEvents = true

            -- Detecta qual celula foi editada (ColumnIndex 1=Metros, 2=R$/m)
            local editRow = -1; local editCol = -1
            try ( editRow = args.RowIndex; editCol = args.ColumnIndex ) catch()

            -- B2 — Redistribuicao de metros:
            -- Quando se edita a coluna Metros (col 1) em uma linha nao-primaria (r > 0),
            -- o delta e subtraido da linha 1 para manter o total = G_CustoFitaMetros.
            if editRow > 0 and editCol == 1 and ::G_FitasMultiLinhas.count > 1 do
            (
                local novoMetros = parseFloatText (gridFitas.Rows.Item[editRow].Cells.Item[1].Value) 0.0
                local metrosAnt  = try (::G_FitasMultiLinhas[editRow + 1][2] as float) catch 0.0
                local delta      = novoMetros - metrosAnt
                local metrosPri  = try (::G_FitasMultiLinhas[1][2] as float) catch 0.0
                local novosPri   = metrosPri - delta
                if novosPri < 0.0 do
                (
                    -- Limite: linha secundaria nao pode tomar mais do que a primaria tem
                    novoMetros += novosPri  -- desconta o excedente
                    novosPri   = 0.0
                    gridFitas.Rows.Item[editRow].Cells.Item[1].Value = (novoMetros as string)
                )
                -- Atualiza linha 1
                local ft1 = ::G_FitasMultiLinhas[1]
                ::G_FitasMultiLinhas[1] = #(ft1[1], novosPri, ft1[3], ft1[4], ft1[5])
                gridFitas.Rows.Item[0].Cells.Item[1].Value = (novosPri as string)
                local sub1 = novosPri * (try (ft1[3] as float) catch 0.0)
                gridFitas.Rows.Item[0].Cells.Item[3].Value = "R$ " + (money sub1)
            )

            -- Sincroniza todas as linhas da grid com G_FitasMultiLinhas
            for r = 0 to gridFitas.Rows.Count - 1 do
            (
                if (r + 1) <= ::G_FitasMultiLinhas.count do
                (
                    local metros = parseFloatText (gridFitas.Rows.Item[r].Cells.Item[1].Value) 0.0
                    local valM   = parseFloatText (gridFitas.Rows.Item[r].Cells.Item[2].Value) 0.0
                    local sub    = metros * valM
                    gridFitas.Rows.Item[r].Cells.Item[3].Value = "R$ " + (money sub)
                    local ft = ::G_FitasMultiLinhas[r + 1]
                    ::G_FitasMultiLinhas[r + 1] = #(ft[1], metros, valM, ft[4], ft[5])
                )
            )
            suppressEvents = false
            recalcular()
        )

        fn onBuscarFerragem sender args =
        (
            if not G_ApiOnline do
            (
                messageBox "API offline." title:"API Offline"
                return undefined
            )
            ::abrirBuscaFerragemAPI()
        )

        fn onAtualizar sender args = refreshFromApi()
        fn onTextChanged sender args = recalcular()
        fn onGridChanged sender args = recalcular()

        -- FIX TECLADO: ao entrar num campo de texto, suspende os aceleradores do 3ds Max
        -- (sem isso, teclas como vírgula, ponto, minus e numpad são interceptadas pelo Max)
        fn onFocusIn  sender args = ( enableAccelerators = false )
        fn onFocusOut sender args = ( enableAccelerators = true  )

        fn showLoading lbl:"Aguarde..." =
        (
            lbLoad.Text    = "|"
            lbLoad.Visible = true
            G_ActiveSpinner = lbLoad
            btnCriarCot.Enabled = false
            lbFooter.Text = lbl
            windows.processPostedMessages()
        )
        fn hideLoading =
        (
            G_ActiveSpinner = undefined
            lbLoad.Visible  = false
            btnCriarCot.Enabled = true
            lbFooter.Text = "Selecione uma linha para buscar preco. Use Atualizar Selecoes apos fechar uma busca."
        )

        -- ── buildPecasJson ──────────────────────────────────────────────
        -- Serializa G_PiecesData em JSON array de pecas agrupadas,
        -- com custo unitario estimado por area × valor_m2 da chapa correspondente.
        -- Retorna string JSON pronta para embedar no payload da cotacao.
        -- DEVE ser definida ANTES de finalizarCotacao (forward-ref nao resolve
        -- entre fns locais de rollout — chamada virava undefined).
        -- ────────────────────────────────────────────────────────────────
        fn buildPecasJson desp =
        (
            -- Agrupa pecas identicas: #(nome, compMm, largMm, espMm, c1, c2, l1, l2, qtd)
            local grupos = #()
            for p in ::G_PiecesData do
            (
                local espMm = (floor (p.esp  * 25.4 * 10 + 0.5)) / 10.0
                local cMm   = (floor (p.comp * 25.4 * 10 + 0.5)) / 10.0
                local lMm   = (floor (p.larg * 25.4 * 10 + 0.5)) / 10.0
                if lMm > cMm do ( local t = cMm; cMm = lMm; lMm = t )
                local achou = false
                for g in grupos do
                (
                    if g[1] == p.nome and abs(g[2]-cMm) < 0.1 and abs(g[3]-lMm) < 0.1 \
                        and abs(g[4]-espMm) < 0.1 and g[5] == p.c1 and g[6] == p.c2 \
                        and g[7] == p.l1 and g[8] == p.l2 do
                    (
                        g[9] += 1; achou = true; exit
                    )
                )
                if not achou do append grupos #(p.nome, cMm, lMm, espMm, p.c1, p.c2, p.l1, p.l2, 1)
            )
            if grupos.count == 0 do return "[]"

            -- Serializa
            local ss = stringStream ""
            format "[" to:ss
            for i = 1 to grupos.count do
            (
                local g = grupos[i]
                local nomeSafe = substituteString g[1] "\"" "'"
                -- Custo unitario do produto: area_m2 × valor_m2 da chapa (SEM fator desperdicio)
                -- Este valor representa o custo proporcional do material que ENTRA no produto
                local areaM2  = (g[2] / 1000.0) * (g[3] / 1000.0)
                local valorM2 = 0.0
                for entry in ::G_ApiChapaPrecos do
                    if abs(entry[1] - g[4]) < 0.5 do ( valorM2 = try (entry[7] as float) catch 0.0; exit )
                -- CMC unitario: area × preco/m2 × (1 + perda real do plano de corte)
                -- Perda derivada do aproveitamento do MAXRECTS; fallback k_perda do INI
                local aprovReal  = try (::G_CustoAprovArred as float) catch 0.0
                local kPerda     = if aprovReal > 1.0 then (100.0 / aprovReal - 1.0) \
                                   else (try (::G_MO_KPerdaSeguranca as float) catch 0.10)
                if kPerda < 0.0 do kPerda = 0.0
                if kPerda > 1.0 do kPerda = 1.0
                local custoUnit  = areaM2 * valorM2 * (1.0 + kPerda)
                local custoTotal = custoUnit * g[9]
                -- Metros de fita por peca
                local fitaM = 0.0
                if g[5] do fitaM += g[2] / 1000.0
                if g[6] do fitaM += g[2] / 1000.0
                if g[7] do fitaM += g[3] / 1000.0
                if g[8] do fitaM += g[3] / 1000.0
                format "{\"nome\":\"%\",\"comp_mm\":%,\"larg_mm\":%,\"esp_mm\":%,\"qtd\":%,\"area_m2\":%,\"fita_m\":%,\"fita_c1\":%,\"fita_c2\":%,\"fita_l1\":%,\"fita_l2\":%,\"preco_m2\":%,\"custo_unit\":%,\"custo_total\":%" \
                    nomeSafe g[2] g[3] g[4] g[9] areaM2 fitaM \
                    (if g[5] then "true" else "false") (if g[6] then "true" else "false") \
                    (if g[7] then "true" else "false") (if g[8] then "true" else "false") \
                    valorM2 custoUnit custoTotal to:ss
                format "}" to:ss
                if i < grupos.count do format "," to:ss
            )
            format "]" to:ss
            ss as string
        )

        -- Chamado pelo modal rlDadosCliente apos confirmacao do cliente/projeto
        fn finalizarCotacao =
        (
            if G_DadosCotacaoCliente.count < 5 do return undefined

            local cliId       = G_DadosCotacaoCliente[1]
            local nomeProjeto = G_DadosCotacaoCliente[2]
            local obsGeral    = G_DadosCotacaoCliente[3]
            local previsao    = G_DadosCotacaoCliente[4]
            local desconto    = G_DadosCotacaoCliente[5]

            showLoading lbl:"Atualizando precos..."
            refreshFromApi()

            local desp   = parseFloatText txtDesp.Text   0.0
            local ferr   = parseFloatText txtFerr.Text   0.0
            local cola   = parseFloatText txtCola.Text   0.0
            local frete  = parseFloatText txtFrete.Text  0.0
            local margem   = try (parseFloatText txtMargemLucro.Text 30.0) catch 30.0
            local imposto  = try (parseFloatText txtImposto.Text  0.0) catch 0.0
            local comissao = try (parseFloatText txtComissao.Text 0.0) catch 0.0

            -- MO: auto ou override manual
            local moManualFinal = try (chkMOManual.Checked) catch false
            local maoObra = if moManualFinal \
                then (parseFloatText txtMOManual.Text 0.0) \
                else (try (::calcularMaoObra()) catch 0.0)

            -- ── CA_Chapas: aquisicao real = chapas inteiras consumidas pelo plano ──
            local chapasArr  = #()
            local precos     = #()
            local caChapas   = 0.0
            for i = 1 to G_ChapasGrupos.count do
            (
                local espMm    = G_ChapasGrupos[i][1]
                local qtd      = G_ChapasGrupos[i][2]
                local preco    = readGridPrice i
                local nomeProd = "Manual"
                local entry    = getChapaEntry espMm
                if entry != undefined do nomeProd = entry[3]
                local sub = qtd * preco
                append chapasArr #(espMm, nomeProd, qtd, preco, sub)
                append precos preco
                caChapas += sub
            )

            -- ── CMC_Fitas: metros consumidos × preco/m  +  CA_Fitas: rolos fechados ──
            local fitasArr  = #()
            local cmcFitas  = 0.0
            local caFitas   = 0.0
            for ft in ::G_FitasMultiLinhas do
            (
                local metros = try (ft[2] as float) catch 0.0
                local valM   = try (ft[3] as float) catch 0.0
                local roloM  = try (ft[4] as float) catch 50.0
                if roloM <= 0.0 do roloM = 50.0
                local sub    = metros * valM
                append fitasArr #(ft[1], metros, valM, sub)
                cmcFitas += sub
                local nRolos = ceil (metros / roloM)
                if metros > 0.0 and nRolos < 1.0 do nRolos = 1.0
                caFitas += nRolos * roloM * valM
            )

            -- ── CMC_Chapas: area × preco/m2 × (1 + perda real do plano) ──
            local aprovReal = try (::G_CustoAprovArred as float) catch 0.0
            local kPerda    = if aprovReal > 1.0 then (100.0 / aprovReal - 1.0) \
                              else (try (::G_MO_KPerdaSeguranca as float) catch 0.10)
            if kPerda < 0.0 do kPerda = 0.0
            if kPerda > 1.0 do kPerda = 1.0
            local cmcChapas = 0.0
            for p in G_PiecesData do
            (
                local espMm  = (floor (p.esp  * 25.4 * 10 + 0.5)) / 10.0
                local areaM2 = (p.comp * 25.4 / 1000.0) * (p.larg * 25.4 / 1000.0)
                local valM2  = 0.0
                for en in ::G_ApiChapaPrecos do
                    if abs(en[1] - espMm) < 0.5 do ( valM2 = try (en[7] as float) catch 0.0; exit )
                cmcChapas += areaM2 * valM2
            )
            cmcChapas *= (1.0 + kPerda)

            -- ── Ferragens (custo real pelas unidades selecionadas) ──
            local totalFerr = 0.0
            for fe in ::G_FerragensLista do
                totalFerr += (try (fe[3] as float) catch 0.0) * (try (fe[5] as integer) catch 1)

            -- ── Totais: PV por markup divisor (margem + imposto + comissao por dentro) ──
            local cmc  = cmcChapas + cmcFitas
            local cob  = cmc + totalFerr + cola + frete + maoObra
            local somaPct = margem + imposto + comissao
            if somaPct > 95.0 do somaPct = 95.0
            local pv      = cob / (1.0 - somaPct / 100.0)
            local pvFinal = pv * (1.0 - desconto / 100.0)

            -- CA Total para referencia interna (aquisicao sem MO)
            local caTotal  = caChapas + caFitas + totalFerr + cola + frete

            -- Trava de margem minima: desconto nao pode levar o preco abaixo do custo
            if pvFinal < cob do
            (
                hideLoading()
                local msgTrava = "ATENCAO: com o desconto de " + (desconto as string) + \
                    "%, o preco final (R$ " + (money pvFinal) + ") fica ABAIXO do custo operacional (COB R$ " + \
                    (money cob) + ").\n\nA cotacao dara PREJUIZO. Continuar mesmo assim?"
                if not (queryBox msgTrava title:"Desconto abaixo do custo") do return undefined
                showLoading lbl:"Registrando cotacao..."
            )

            -- ── outrosArr para o payload (mantem ferragem, cola, MO, frete) ──
            local outrosArr = #(totalFerr, cola, maoObra, frete)
            local totalOut  = totalFerr + cola + maoObra + frete

            local cotId = 0
            local ferragensParam = ::G_FerragensLista
            -- Serializa pecas_json (custo_unit ja inclui k_perda via buildPecasJson)
            local pecasJsonStr = "[]"
            try ( pecasJsonStr = buildPecasJson desp )
            catch ( ::apiAppendLog "maxscript_api_errors.log" ("buildPecasJson: " + (getCurrentException())) )

            showLoading lbl:"Registrando cotacao..."
            if G_ApiOnline then
            (
                local res = ::apiCriarCotacao chapasArr fitasArr outrosArr desp G_CustoAprovArred \
                    caChapas cmcFitas totalOut pvFinal \
                    clienteId:cliId nomeProjeto:nomeProjeto \
                    previsaoEntrega:previsao descontoGlobal:desconto obsGeral:obsGeral \
                    custoEfetivoChapas:caChapas custoEfetivoFitas:caFitas \
                    custoEfetivoOutros:(totalFerr + cola + frete) custoEfetivoGeral:caTotal \
                    custoProductoChapas:cmcChapas custoProductoFitas:cmcFitas \
                    custoProductoOutros:(totalFerr + frete) custoProductoGeral:cmc \
                    ferragensLista:ferragensParam pecasJson:pecasJsonStr \
                    maoObra:maoObra moManual:moManualFinal \
                    custoAquisicaoTotal:caTotal custoMaterialConsumido:cmc \
                    custoOperacionalBase:cob margemLucroPct:margem precoVendaFinal:pvFinal \
                    impostoPct:imposto comissaoPct:comissao
                if res[1] then
                (
                    cotId = res[2]
                    messageBox res[3] title:"Cotacao Criada"
                )
                else
                (
                    messageBox ("Aviso API: " + res[3] + "\nPlanilha sera gerada sem registro no banco.") title:"Aviso"
                )
            )

            hideLoading()
            local fitaPrecoExcel = if ::G_FitasMultiLinhas.count > 0 then (try (::G_FitasMultiLinhas[1][3] as float) catch 0.0) else 0.0
            ::gerarPlanilhaExcel precos desp fitaPrecoExcel totalFerr cola maoObra frete cotacaoId:cotId \
                custoAquisicaoGeral:caTotal custoProdutoGeral:cmc \
                pecasJsonStr:pecasJsonStr moManual:moManualFinal \
                margemPct:margem impostoPct:imposto comissaoPct:comissao \
                precoVenda:pv precoVendaFinal:pvFinal \
                custoFitaTotal:cmcFitas custoFitaAquisicao:caFitas cobTotal:cob
        )

        -- Abre o modal de dados do cliente; finalizarCotacao e chamado pelo modal ao confirmar
        fn iniciarCotacao =
        (
            G_DadosCotacaoCliente = #()
            ::abrirDadosCliente()
        )

        fn buildUi =
        (
            pnl.Controls.Clear()

            -- ── Resumo do Plano ──
            local grpResumo = addGroup pnl "Resumo do Plano" 8 8 946 74
            addLabel grpResumo ("Chapas utilizadas: " + (G_CustoNChapas as string)) 14 26 180 18
            addLabel grpResumo ("Aproveitamento: " + (G_CustoAprovArred as string) + " pct") 214 26 190 18
            addLabel grpResumo ("Fita de borda total estimada: " + (G_CustoFitaArred as string) + " m") 424 26 260 18
            addLabel grpResumo (if G_ApiOnline then "API: Conectada" else "API: Offline") 730 26 208 18

            -- ── Chapas por Espessura ──
            local grpChapas = addGroup pnl "Chapas por Espessura" 8 90 946 255
            gridChapas = dotNetObject "System.Windows.Forms.DataGridView"
            gridChapas.Location = dnPoint 14 24
            gridChapas.Size = dnSize 914 170
            grpChapas.Controls.Add gridChapas
            btnBuscarChapa = addButton grpChapas "Buscar Chapa Selecionada na API" 14 206 240 28
            btnAtualizar   = addButton grpChapas "Atualizar Selecoes" 270 206 170 28
            addLabel grpChapas "Edite o valor R$/chapa manualmente quando nao houver produto selecionado." 460 212 440 18

            -- ── Fita de Borda (multi-produto) ──
            local grpCustos = addGroup pnl "Fita de Borda" 8 354 550 290
            addLabel grpCustos ("Desperdicio estimado: " + (G_CustoDespEst as string) + "%") 14 22 280 18
            addLabel grpCustos "Desperdicio aplicado (%)" 14 48 170 18
            txtDesp = addText grpCustos (G_CustoDespEst as string) 192 44 80 24
            addLabel grpCustos "Fitas selecionadas — edite Metros e R$/m diretamente na grade:" 14 80 520 18
            -- Grid de fitas multiplas
            gridFitas = dotNetObject "System.Windows.Forms.DataGridView"
            gridFitas.Location = dnPoint 14 100
            gridFitas.Size = dnSize 520 120
            gridFitas.AllowUserToAddRows    = false
            gridFitas.AllowUserToDeleteRows = false
            gridFitas.RowHeadersVisible     = false
            gridFitas.MultiSelect           = false
            gridFitas.SelectionMode = (dotNetClass "System.Windows.Forms.DataGridViewSelectionMode").FullRowSelect
            gridFitas.EditMode = (dotNetClass "System.Windows.Forms.DataGridViewEditMode").EditOnEnter
            local fc0 = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"
            fc0.Name = "nome"; fc0.HeaderText = "Produto"; fc0.Width = 210; fc0.ReadOnly = true
            local fc1 = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"
            fc1.Name = "metros"; fc1.HeaderText = "Metros (m)"; fc1.Width = 80; fc1.ReadOnly = false
            local fc2 = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"
            fc2.Name = "valm"; fc2.HeaderText = "R$/m"; fc2.Width = 70; fc2.ReadOnly = false
            local fc3 = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"
            fc3.Name = "sub"; fc3.HeaderText = "Subtotal"; fc3.Width = 110; fc3.ReadOnly = true
            gridFitas.Columns.Add fc0; gridFitas.Columns.Add fc1
            gridFitas.Columns.Add fc2; gridFitas.Columns.Add fc3
            grpCustos.Controls.Add gridFitas
            btnBuscarFita    = addButton grpCustos "Buscar Fita na API" 14 232 186 28
            btnAdicionarFita = addButton grpCustos "+ Fita"             210 232 90  28
            btnRemoverFita   = addButton grpCustos "- Remover"          310 232 110 28

            -- ── Outros Custos ──
            local grpOutros = addGroup pnl "Outros Custos" 566 354 388 366
            addLabel grpOutros "Ferragem (R$)"             14 28  120 18
            txtFerr = addText grpOutros "0.0"              140 24  90  24
            btnBuscarFerragem = addButton grpOutros "Buscar Ferragem na API" 240 24 138 24
            lbFerragensInfo = addLabel grpOutros "Nenhuma ferragem selecionada" 14 56 366 28
            addLabel grpOutros "Cola (R$)"                 14 92  120 18
            txtCola = addText grpOutros "0.0"              140 88  90  24

            -- Mao de Obra: auto-calculada, com opcao de override manual
            addLabel grpOutros "Mao de Obra"               14 120 130 18
            lbMOEstimada = addLabel grpOutros "Auto: R$ 0.00" 150 120 220 18
            local chkColor = dotNetClass "System.Drawing.Color"
            try ( lbMOEstimada.ForeColor = chkColor.FromArgb 80 120 80 ) catch()

            -- Checkbox para override manual
            chkMOManual = dotNetObject "System.Windows.Forms.CheckBox"
            chkMOManual.Text = "Substituir por valor manual"
            chkMOManual.Location = (dnPoint 14 144)
            chkMOManual.Size = (dnSize 250 20)
            chkMOManual.Checked = false
            grpOutros.Controls.Add chkMOManual

            -- Campo de override (inicia desabilitado)
            txtMOManual = addText grpOutros "0.0"          270 142 100 24
            txtMOManual.Enabled = false

            addLabel grpOutros "Transporte / Frete (R$)"   14 192 150 18
            txtFrete = addText grpOutros "0.0"             172 188 90  24

            addLabel grpOutros "Margem de Lucro (%)"       14 224 150 18
            txtMargemLucro = addText grpOutros "30.0"      172 220 90  24

            addLabel grpOutros "Imposto (%)"               14 256 150 18
            txtImposto = addText grpOutros "0.0"           172 252 90  24

            addLabel grpOutros "Comissao (%)"              14 288 150 18
            txtComissao = addText grpOutros "0.0"          172 284 90  24

            -- ── Resultado (modelo CMC + Markup) ──
            local grpResultado = addGroup pnl "Resultado" 8 728 946 148
            -- Coluna esquerda: decomposicao de insumos
            lbRch  = addLabel grpResultado "CA Chapas (c/ desp.): R$ --"  8  16 380 18
            lbRft  = addLabel grpResultado "CMC Fitas: R$ --"             8  36 380 18
            lbRou  = addLabel grpResultado "Ferragens: R$ --"             8  56 380 18
            lbRfr  = addLabel grpResultado "Cola + Frete: R$ --"         8  76 380 18
            lbRmo  = addLabel grpResultado "Mao de Obra: R$ --"          8  96 380 18
            -- Coluna direita: resumo financeiro
            lbCMC     = addLabel grpResultado "CMC (mat. consumido): R$ --"  394 16 544 18
            lbCOB     = addLabel grpResultado "COB (custo operacional): R$ --" 394 38 544 18
            lbMO      = addLabel grpResultado "Margem Lucro: --% sobre COB"  394 60 544 18
            lbTot     = addLabel grpResultado "PRECO DE VENDA: R$ --"       394 84 544 26
            lbEfetivo = addLabel grpResultado "CA Total (aquisicao): R$ --" 394 114 544 18
            lbProduto = addLabel grpResultado ""                            394 132 544 18

            setupGrid()
            refreshChapasGrid()

            -- Inicializa fitas se necessario
            if ::G_FitasMultiLinhas.count == 0 do
            (
                if G_ApiFitaPrecos.count > 0 then
                (
                    local ft = G_ApiFitaPrecos[1]
                    local forn = if ft.count >= 6 then ft[6] else ""
                    ::G_FitasMultiLinhas = #(#(ft[3], G_CustoFitaMetros, ft[2], ft[4], forn))
                )
                else
                (
                    ::G_FitasMultiLinhas = #(#("(Selecionar na API)", G_CustoFitaMetros, 0.0, 50.0, ""))
                )
            )
            refreshFitasGrid()
            refreshFerragensInfo()

            -- Registra eventos
            dotNet.addEventHandler btnBuscarChapa    "Click"            onBuscarChapa
            dotNet.addEventHandler btnAtualizar      "Click"            onAtualizar
            dotNet.addEventHandler btnBuscarFita     "Click"            onBuscarFita
            dotNet.addEventHandler btnAdicionarFita  "Click"            onAdicionarFita
            dotNet.addEventHandler btnRemoverFita    "Click"            onRemoverFita
            dotNet.addEventHandler btnBuscarFerragem "Click"            onBuscarFerragem
            dotNet.addEventHandler gridChapas        "CellValueChanged" onGridChanged
            dotNet.addEventHandler gridFitas         "CellValueChanged" onFitasGridChanged
            for tb in #(txtDesp, txtFerr, txtCola, txtFrete, txtMOManual, txtMargemLucro, txtImposto, txtComissao) do
            (
                dotNet.addEventHandler tb "TextChanged" onTextChanged
                dotNet.addEventHandler tb "GotFocus"    onFocusIn
                dotNet.addEventHandler tb "LostFocus"   onFocusOut
            )
            dotNet.addEventHandler chkMOManual "CheckedChanged" onTextChanged

            recalcular()
        )

        on rlCusto open do
        (
            -- Reseta listas de fita e ferragens para nova cotacao
            ::G_FitasMultiLinhas = #()
            ::G_FerragensLista   = #()
            btnCriarCot.Text  = "Criar Cotacao e Gerar Planilha"
            btnClose.Text     = "Fechar"
            btnCotacoes.Text  = "Ver Cotacoes"
            lbFooter.Text     = "Selecione uma linha de chapa para buscar preco. Edite Metros/R$/m na grade de fitas."
            lbLoad.Visible    = false
            buildUi()
            try ( ::aplicarTemaForm lbLoad.FindForm() ) catch()
            ::pintarBotaoProximo btnCriarCot
            ::pintarBotaoCancelar btnClose
            try ( ::pintarBotaoPesquisar btnBuscarChapa ) catch()
            try ( ::pintarBotaoAtualizar btnAtualizar ) catch()
            try ( ::pintarBotaoPesquisar btnBuscarFita ) catch()
            try ( ::pintarBotaoPesquisar btnBuscarFerragem ) catch()
        )

        on btnCriarCot  Click sender args do iniciarCotacao()
        on btnCotacoes  Click sender args do ( destroyDialog rlCusto; ::abrirCotacoes() )
        on btnClose     Click sender args do destroyDialog rlCusto
    )

    G_ActiveCustoRl = rlCusto
    createDialog rlCusto style:#(#style_titlebar, #style_border, #style_sysmenu) bgcolor:(color 245 246 248)
)
-- FEATURE 2: EXPORTAÃ‡ÃƒO PDF
-- ============================================================
fn exportarPlanoPDF pdfPath aproveitamento totalChapas =
(
    local pyScript = (dirSep G_ScriptDir) + "cnc_export_pdf.py"
    local tmpDir   = dirSep sysInfo.tempDir
    local dataFile = tmpDir + "cnc_pdf_data.txt"

    -- Escreve arquivo de dados para o Python
    local fOut = openFile dataFile mode:"wt"
    if fOut == undefined do ( messageBox "Erro ao criar dados para PDF." title:"Erro PDF"; return undefined )

    format "pdf_path=%\n"       pdfPath         to:fOut
    format "aproveitamento=%\n" aproveitamento  to:fOut
    format "total_chapas=%\n"   totalChapas     to:fOut

    -- Chapas
    format "chapas_count=%\n" G_PdfChapas.count to:fOut
    for c in G_PdfChapas do
        format "chapa,%,%,%,%,%,%\n" c[1] c[2] c[3] c[4] c[5] c[6] to:fOut

    -- PeÃ§as
    format "pecas_count=%\n" G_PdfPecas.count to:fOut
    for p in G_PdfPecas do
    (
        local nm   = p[1]
        local wm   = p[2]; local dm  = p[3]
        local bIdx = p[4]
        local px   = p[5] * 25.4; local py = p[6] * 25.4
        local offX = p[7] * 25.4; local esp = p[8] * 25.4
        format "peca,%,%,%,%,%,%,%,%\n" nm wm dm bIdx px py offX esp to:fOut
    )
    close fOut

    python.ExecuteFile pyScript
    local err = python.GetLastError()
    if err != "" then
        messageBox ("Erro ao gerar PDF:\n" + err) title:"Erro PDF"
    else
        format "PDF exportado: %\n" pdfPath
)

-- ============================================================
-- FASE 2: UI FITAS DE BORDA (Dinamica)
-- ============================================================
fn abrirUIFitas =
(
    if fltFitas != undefined do
    (
        try ( destroyDialog fltFitas ) catch ( try ( closeRolloutFloater fltFitas ) catch() )
        fltFitas = undefined
    )

    rollout rlFitas "Fitas e Acabamento" width:890 height:600
    (
        dotNetControl grid "System.Windows.Forms.DataGridView" pos:[12,92] width:864 height:420
        dotNetControl cmbEsp "System.Windows.Forms.ComboBox" pos:[154,18] width:120 height:24
        dotNetControl chkC1 "System.Windows.Forms.CheckBox" pos:[260,54] width:70 height:22
        dotNetControl chkC2 "System.Windows.Forms.CheckBox" pos:[340,54] width:70 height:22
        dotNetControl chkL1 "System.Windows.Forms.CheckBox" pos:[420,54] width:70 height:22
        dotNetControl chkL2 "System.Windows.Forms.CheckBox" pos:[500,54] width:70 height:22
        dotNetControl btnGo    "System.Windows.Forms.Button" pos:[616,535] width:260 height:34
        dotNetControl btnCancel "System.Windows.Forms.Button" pos:[12,535]  width:140 height:34
        dotNetControl lbTitle  "System.Windows.Forms.Label"  pos:[12,18]   width:220 height:18
        dotNetControl lbHint   "System.Windows.Forms.Label"  pos:[12,56]   width:100 height:18
        dotNetControl lbCount  "System.Windows.Forms.Label"  pos:[170,542] width:380 height:18

        fn dnColText name header width readOnly:true =
        (
            local col = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"
            col.Name = name
            col.HeaderText = header
            col.Width = width
            col.ReadOnly = readOnly
            col
        )

        fn dnColCheck name header width =
        (
            local col = dotNetObject "System.Windows.Forms.DataGridViewCheckBoxColumn"
            col.Name = name
            col.HeaderText = header
            col.Width = width
            col
        )

        fn setupGrid =
        (
            grid.AllowUserToAddRows = false
            grid.AllowUserToDeleteRows = false
            grid.RowHeadersVisible = false
            grid.SelectionMode = (dotNetClass "System.Windows.Forms.DataGridViewSelectionMode").FullRowSelect
            grid.AutoSizeRowsMode = (dotNetClass "System.Windows.Forms.DataGridViewAutoSizeRowsMode").AllCells
            grid.Columns.Clear()
            grid.Columns.Add (dnColText "nome" "Peca" 260)
            grid.Columns.Add (dnColText "comp" "Comp." 80)
            grid.Columns.Add (dnColText "larg" "Larg." 80)
            grid.Columns.Add (dnColText "esp" "Esp." 60)
            grid.Columns.Add (dnColCheck "c1" "C1" 54)
            grid.Columns.Add (dnColCheck "c2" "C2" 54)
            grid.Columns.Add (dnColCheck "l1" "L1" 54)
            grid.Columns.Add (dnColCheck "l2" "L2" 54)
            grid.Columns.Add (dnColText "fita_m" "Fita estimada" 105)

            for p in G_PiecesData do
            (
                local idx = grid.Rows.Add()
                local row = grid.Rows.Item[idx]
                row.Cells.Item[0].Value = p.nome
                row.Cells.Item[1].Value = ((floor(p.comp*25.4*10+0.5))/10.0) as string
                row.Cells.Item[2].Value = ((floor(p.larg*25.4*10+0.5))/10.0) as string
                row.Cells.Item[3].Value = ((floor(p.esp*25.4*10+0.5))/10.0) as string
                row.Cells.Item[4].Value = p.c1
                row.Cells.Item[5].Value = p.c2
                row.Cells.Item[6].Value = p.l1
                row.Cells.Item[7].Value = p.l2
                row.Cells.Item[8].Value = "-"
            )
            lbCount.Text = (G_PiecesData.count as string) + " peca(s) detectada(s)"
        )

        fn setColChecked colIdx state =
        (
            for r = 0 to grid.Rows.Count-1 do grid.Rows.Item[r].Cells.Item[colIdx].Value = state
        )

        fn cellChecked rowIdx colIdx =
        (
            local v = grid.Rows.Item[rowIdx].Cells.Item[colIdx].Value
            if v == true then true else false
        )

        fn onCheckC1 sender args = setColChecked 4 chkC1.Checked
        fn onCheckC2 sender args = setColChecked 5 chkC2.Checked
        fn onCheckL1 sender args = setColChecked 6 chkL1.Checked
        fn onCheckL2 sender args = setColChecked 7 chkL2.Checked

        fn onCancel sender args =
        (
            destroyDialog rlFitas
            fltFitas = undefined
        )

        fn onConfirm sender args =
        (
            for i = 1 to G_PiecesData.count do
            (
                local r = i - 1
                G_PiecesData[i].c1 = cellChecked r 4
                G_PiecesData[i].c2 = cellChecked r 5
                G_PiecesData[i].l1 = cellChecked r 6
                G_PiecesData[i].l2 = cellChecked r 7
            )

            local fitaVals = #(0.45, 1.0, 1.5, 2.0, 3.0)
            if cmbEsp.SelectedIndex >= 0 then
                G_FitaTh = fitaVals[cmbEsp.SelectedIndex + 1]
            else
                G_FitaTh = try ((substituteString cmbEsp.Text "," ".") as float) catch (1.0)

            destroyDialog rlFitas
            fltFitas = undefined
            executarMotorDeCorte()
        )

        on rlFitas open do
        (
            lbTitle.Text = "Aplicacao de fitas por peca"
            lbHint.Text  = "Marcar todos:"
            lbCount.Text = ""

            cmbEsp.DropDownStyle = (dotNetClass "System.Windows.Forms.ComboBoxStyle").DropDownList
            for item in #("0.45", "1.0", "1.5", "2.0", "3.0") do cmbEsp.Items.Add item
            cmbEsp.SelectedIndex = 1

            chkC1.Text = "C1"
            chkC2.Text = "C2"
            chkL1.Text = "L1"
            chkL2.Text = "L2"
            btnGo.Text     = "Confirmar e Gerar Plano"
            btnCancel.Text = "← Voltar"

            setupGrid()
            try ( ::aplicarTemaForm lbTitle.FindForm() ) catch()
            try ( cmbEsp.DropDownStyle = (dotNetClass "System.Windows.Forms.ComboBoxStyle").DropDown ) catch()
            try ( cmbEsp.Text = cmbEsp.Items.Item[cmbEsp.SelectedIndex] ) catch()
            try ( cmbEsp.BackColor = (dotNetClass "System.Drawing.Color").White ) catch()
            try ( cmbEsp.ForeColor = (dotNetClass "System.Drawing.Color").FromArgb 27 32 38 ) catch()
            ::pintarBotaoProximo btnGo
        )

        on chkC1 CheckedChanged sender args do onCheckC1 sender args
        on chkC2 CheckedChanged sender args do onCheckC2 sender args
        on chkL1 CheckedChanged sender args do onCheckL1 sender args
        on chkL2 CheckedChanged sender args do onCheckL2 sender args
        on btnGo Click sender args do onConfirm sender args
        on btnCancel Click sender args do onCancel sender args
    )

    fltFitas = rlFitas
    createDialog rlFitas style:#(#style_titlebar, #style_border, #style_sysmenu) bgcolor:(color 245 246 248)
)
-- ============================================================
-- FASE 1: PREPARAÃ‡ÃƒO DAS PEÃ‡AS E UI INICIAL
-- ============================================================
fn processarFase1 binW binD gap borda sufixo expDWG alignMode groupMode =
(
    -- Feature 0: verificacao melhorada de selecao
    if selection.count == 0 do
    (
        messageBox "Nenhum objeto selecionado!\n\nSelecione os paineis na cena e tente novamente." \
            title:"Aviso — Sem Selecao"
        return undefined
    )
    local nValidos = 0
    for obj in selection do if (iskindof obj GeometryClass) do nValidos += 1
    if nValidos == 0 do
    (
        messageBox ("Os " + (selection.count as string) + " objeto(s) selecionado(s) nao possuem geometria valida.\n" + \
            "Selecione paineis (mesh ou poly) e tente novamente.") \
            title:"Aviso — Geometria Invalida"
        return undefined
    )
    if nValidos < selection.count do
        format "AVISO: % objeto(s) ignorado(s) por nao terem geometria valida.\n" (selection.count - nValidos)

    G_MainConfig      = #(binW, binD, gap, borda, expDWG, alignMode, groupMode)
    G_PiecesData      = #()
    G_OriginalDims    = #()
    G_TotalFitaMetros = 0.0

    local tempObjs = #()
    for obj in selection do
    (
        local copia = copy obj; copia.name = obj.name + sufixo; copia.isHidden = false
        ResetXForm copia; convertTo copia Editable_Poly; copia.pivot = copia.center
        append tempObjs copia
    )

    for obj in tempObjs do
    (
        try
        (
            -- Alinha o painel pela normal da maior face (correto para qualquer angulaÃ§Ã£o)
            alinharPelaFaceMaior obj

            local bbFinal = nodeGetBoundingBox obj (matrix3 1)
            local w   = abs(bbFinal[2].x - bbFinal[1].x)
            local d   = abs(bbFinal[2].y - bbFinal[1].y)
            local esp = abs(bbFinal[2].z - bbFinal[1].z)

            if d > w do ( local t=w; w=d; d=t )

            local origNameLen = obj.name.count - sufixo.count
            local nomeReal = if origNameLen > 0 then substring obj.name 1 origNameLen else obj.name

            -- Aviso se espessura detectada parecer fora do padrÃ£o MDF/MDP
            local menorFace = if w < d then w else d
            if esp > (menorFace * 0.40) do
                format "AVISO: % â€” espessura detectada: % mm (pode ser objeto 3D complexo)\n" \
                    nomeReal (floor(esp*25.4*10+0.5)/10.0)

            append G_PiecesData  (PieceObj node:obj nome:nomeReal comp:w larg:d esp:esp c1:false c2:false l1:false l2:false)
            append G_OriginalDims #(nomeReal, w * 25.4, d * 25.4, esp * 25.4)
        ) catch()
    )

    -- Aqui ocorre a mÃ¡gica do agrupamento natural!
    qsort G_PiecesData sortPiecesByName

    abrirUIFitas()
)

CHAPAS_NOMES = #("--- MDF ---", "MDF 1830 x 2750 mm", "MDF 1830 x 2200 mm", "MDF 1550 x 2750 mm", "MDF 1220 x 2440 mm", "--- PERSONALIZADO ---", "Personalizado")
CHAPAS_W = #( 0, 1830,1830,1550,1220, 0, 0 )
CHAPAS_D = #( 0, 2750,2200,2750,2440, 0, 0 )

fn abrirUIPrincipal =
(
    rollout rlConfig "Plano de Corte CNC" width:780 height:540
    (
        dotNetControl tabs "System.Windows.Forms.TabControl" pos:[10,10] width:760 height:455
        dotNetControl btnAvan   "System.Windows.Forms.Button" pos:[530,480] width:230 height:34
        dotNetControl btnCancel "System.Windows.Forms.Button" pos:[10,480]  width:120 height:34
        dotNetControl lbFooter  "System.Windows.Forms.Label"  pos:[145,489] width:365 height:18

        local pageProjeto, pageCorte, pageStatus, pageMaoObra
        local cmbChapa, txtW, txtD, txtGap, txtBorda, cmbAlign, cmbGroup, chkDWG, lblApi
        local txtMOBase, txtMOKPeca, txtMOKCorte, txtMOKFita, txtMOKFerr, txtMOKPeso, txtMODens, txtMOKPerda

        fn dnPoint x y = dotNetObject "System.Drawing.Point" x y
        fn dnSize w h = dotNetObject "System.Drawing.Size" w h

        fn addLabel parent text x y w h =
        (
            local c = dotNetObject "System.Windows.Forms.Label"
            c.Text = text
            c.Location = dnPoint x y
            c.Size = dnSize w h
            c
        )

        fn addText parent text x y w h =
        (
            local c = dotNetObject "System.Windows.Forms.TextBox"
            c.Text = text
            c.Location = dnPoint x y
            c.Size = dnSize w h
            parent.Controls.Add c
            c
        )

        fn addCombo parent x y w h =
        (
            local c = dotNetObject "System.Windows.Forms.ComboBox"
            c.DropDownStyle = (dotNetClass "System.Windows.Forms.ComboBoxStyle").DropDownList
            c.Location = dnPoint x y
            c.Size = dnSize w h
            parent.Controls.Add c
            c
        )

        fn addCheck parent text x y w h checked:false =
        (
            local c = dotNetObject "System.Windows.Forms.CheckBox"
            c.Text = text
            c.Location = dnPoint x y
            c.Size = dnSize w h
            c.Checked = checked
            parent.Controls.Add c
            c
        )

        fn addInfo parent title body x y w h =
        (
            local box = dotNetObject "System.Windows.Forms.GroupBox"
            box.Text = title
            box.Location = dnPoint x y
            box.Size = dnSize w h
            local lb = addLabel box body 14 24 (w-28) (h-32)
            lb.AutoSize = false
            box.Controls.Add lb
            parent.Controls.Add box
            box
        )

        fn txtFloat tb defaultVal =
        (
            local raw = substituteString tb.Text "," "."
            local val = defaultVal
            try (val = raw as float) catch (val = defaultVal)
            val
        )

        fn fillCombo cb items sel =
        (
            cb.Items.Clear()
            for item in items do cb.Items.Add item
            cb.SelectedIndex = sel - 1
        )

        fn setTextLocked tb locked =
        (
            local Color = dotNetClass "System.Drawing.Color"
            tb.Enabled = true
            tb.ReadOnly = locked
            tb.BackColor = Color.White
            tb.ForeColor = Color.FromArgb 27 32 38
        )

        -- BUG1: suspende aceleradores do Max em campos de texto dinamicos
        fn onFocusIn  sender args = ( enableAccelerators = false )
        fn onFocusOut sender args = ( enableAccelerators = true  )

        fn styleMainButton btn baseColor hoverColor downColor =
        (
            local Color = dotNetClass "System.Drawing.Color"
            local FlatStyle = dotNetClass "System.Windows.Forms.FlatStyle"
            btn.FlatStyle = FlatStyle.Flat
            try ( btn.UseVisualStyleBackColor = false ) catch()
            btn.BackColor = baseColor
            btn.ForeColor = Color.White
            btn.FlatAppearance.BorderColor = baseColor
            btn.FlatAppearance.MouseOverBackColor = hoverColor
            btn.FlatAppearance.MouseDownBackColor = downColor
        )

        fn polishMainUi =
        (
            local Color = dotNetClass "System.Drawing.Color"
            local TabAppearance = dotNetClass "System.Windows.Forms.TabAppearance"
            local TabSizeMode = dotNetClass "System.Windows.Forms.TabSizeMode"

            try ( tabs.Appearance = TabAppearance.FlatButtons ) catch()
            try ( tabs.SizeMode = TabSizeMode.Fixed ) catch()
            try ( tabs.ItemSize = dotNetObject "System.Drawing.Size" 86 24 ) catch()
            try ( tabs.BackColor = Color.FromArgb 245 246 248 ) catch()
            try ( tabs.ForeColor = Color.FromArgb 27 32 38 ) catch()

            for p = 0 to tabs.TabPages.Count - 1 do
            (
                local pg = tabs.TabPages.Item[p]
                try ( pg.BackColor = Color.FromArgb 245 246 248 ) catch()
                try ( pg.ForeColor = Color.FromArgb 27 32 38 ) catch()
            )

            try ( cmbChapa.BackColor = Color.White ) catch()
            try ( cmbChapa.ForeColor = Color.FromArgb 27 32 38 ) catch()
            try ( cmbChapa.FlatStyle = (dotNetClass "System.Windows.Forms.FlatStyle").Flat ) catch()
            try ( cmbChapa.DropDownStyle = (dotNetClass "System.Windows.Forms.ComboBoxStyle").DropDown ) catch()
            try ( if cmbChapa.SelectedIndex >= 0 do cmbChapa.Text = cmbChapa.Items.Item[cmbChapa.SelectedIndex] ) catch()

            styleMainButton btnAvan (Color.FromArgb 46 139 87) (Color.FromArgb 36 119 73) (Color.FromArgb 26 99 60)
            ::pintarBotaoProximo btnAvan
        )

        fn onChapaChanged sender args =
        (
            local idx = cmbChapa.SelectedIndex + 1
            if idx < 1 do idx = 1
            local w = CHAPAS_W[idx]
            local d = CHAPAS_D[idx]
            if w > 0 and d > 0 then
            (
                txtW.Text = w as string
                txtD.Text = d as string
                setTextLocked txtW true
                setTextLocked txtD true
            )
            else
            (
                setTextLocked txtW false
                setTextLocked txtD false
                if CHAPAS_NOMES[idx] == "Personalizado" do
                (
                    txtW.Text = "1830"
                    txtD.Text = "2750"
                )
            )
        )

        fn onCancel sender args = ( destroyDialog rlConfig; ::abrirCotacoes() )

        fn onAdvance sender args =
        (
            local wMm = txtFloat txtW 0.0
            local dMm = txtFloat txtD 0.0
            local gapMm = txtFloat txtGap 5.0
            local bordaMm = txtFloat txtBorda 15.0

            if wMm <= 0 or dMm <= 0 then
            (
                messageBox "Defina dimensoes validas para a chapa." title:"Aviso"
                return undefined
            )

            -- BUG4: verificar selecao ANTES de fechar o dialog para nao crashar
            if selection.count == 0 do
            (
                messageBox "Nenhum objeto selecionado!\n\nSelecione os paineis na cena antes de avancar." \
                    title:"Aviso — Sem Selecao"
                return undefined
            )
            local nValidos = 0
            for obj in selection do if (iskindof obj GeometryClass) do nValidos += 1
            if nValidos == 0 do
            (
                messageBox ("Os " + (selection.count as string) + " objeto(s) selecionado(s) nao possuem geometria valida.\n" + \
                    "Selecione paineis (mesh ou poly) e tente novamente.") \
                    title:"Aviso — Geometria Invalida"
                return undefined
            )

            local binW = wMm / 25.4
            local binD = dMm / 25.4
            local gap = gapMm / 25.4
            local borda = bordaMm / 25.4
            local sufixo = "_MED"
            local expDWG = chkDWG.Checked
            local alignMode = cmbAlign.SelectedIndex + 1
            local groupMode = cmbGroup.SelectedIndex + 1

            -- Salva coeficientes de MO no INI antes de avancar.
            -- Usa G_TxtMO* (globais) porque txtMOBase etc. sao locais de
            -- buildMaoObra e estariam undefined aqui sem esse indirecionamento.
            try
            (
                local pf v
                if ::G_TxtMOBase   != undefined do ( pf = substituteString ::G_TxtMOBase.Text   "," "."; v = 50.0;  try (v = pf as float) catch(); ::G_MO_BasFixa         = v )
                if ::G_TxtMOKPeca  != undefined do ( pf = substituteString ::G_TxtMOKPeca.Text  "," "."; v = 2.5;   try (v = pf as float) catch(); ::G_MO_KPeca           = v )
                if ::G_TxtMOKCorte != undefined do ( pf = substituteString ::G_TxtMOKCorte.Text "," "."; v = 0.8;   try (v = pf as float) catch(); ::G_MO_KCorteM         = v )
                if ::G_TxtMOKFita  != undefined do ( pf = substituteString ::G_TxtMOKFita.Text  "," "."; v = 0.3;   try (v = pf as float) catch(); ::G_MO_KFita           = v )
                if ::G_TxtMOKFerr  != undefined do ( pf = substituteString ::G_TxtMOKFerr.Text  "," "."; v = 5.0;   try (v = pf as float) catch(); ::G_MO_KFerragem       = v )
                if ::G_TxtMOKPeso  != undefined do ( pf = substituteString ::G_TxtMOKPeso.Text  "," "."; v = 0.2;   try (v = pf as float) catch(); ::G_MO_KPeso           = v )
                if ::G_TxtMODens   != undefined do ( pf = substituteString ::G_TxtMODens.Text   "," "."; v = 700.0; try (v = pf as float) catch(); ::G_MO_Densidade       = v )
                if ::G_TxtMOKPerda != undefined do ( pf = substituteString ::G_TxtMOKPerda.Text "," "."; v = 0.10;  try (v = pf as float) catch(); ::G_MO_KPerdaSeguranca = v )
                ::saveMOConfig()
            ) catch()

            destroyDialog rlConfig
            processarFase1 binW binD gap borda sufixo expDWG alignMode groupMode
        )

        fn buildProjeto =
        (
            pageProjeto = dotNetObject "System.Windows.Forms.TabPage" "Projeto"
            tabs.TabPages.Add pageProjeto

            local lb1 = addLabel pageProjeto "Material / tamanho da chapa" 18 20 220 22
            pageProjeto.Controls.Add lb1
            cmbChapa = addCombo pageProjeto 18 46 330 24
            fillCombo cmbChapa CHAPAS_NOMES 2

            local lbW = addLabel pageProjeto "Largura total X (mm)" 18 92 160 20
            local lbD = addLabel pageProjeto "Profundidade total Y (mm)" 198 92 180 20
            pageProjeto.Controls.Add lbW
            pageProjeto.Controls.Add lbD
            txtW = addText pageProjeto (CHAPAS_W[2] as string) 18 116 150 24
            txtD = addText pageProjeto (CHAPAS_D[2] as string) 198 116 150 24
            setTextLocked txtW true
            setTextLocked txtD true

            chkDWG = addCheck pageProjeto "Exportar 2D para DWG ao finalizar" 18 172 320 24 checked:true
            addInfo pageProjeto "Fluxo" "1. Configure a chapa e as regras de corte.\n2. Avance para escolher as fitas por peca.\n3. O plano sera calculado, exportado e enviado para custos." 390 28 330 150

            dotNet.addEventHandler cmbChapa "SelectedIndexChanged" onChapaChanged
            -- BUG1: habilita digitacao numerica nos campos de dimensao
            dotNet.addEventHandler txtW "GotFocus"  onFocusIn
            dotNet.addEventHandler txtW "LostFocus" onFocusOut
            dotNet.addEventHandler txtD "GotFocus"  onFocusIn
            dotNet.addEventHandler txtD "LostFocus" onFocusOut
        )

        fn buildCorte =
        (
            pageCorte = dotNetObject "System.Windows.Forms.TabPage" "Corte"
            tabs.TabPages.Add pageCorte

            local lbGap = addLabel pageCorte "Gap da fresa / espacamento (mm)" 18 26 250 20
            local lbBorda = addLabel pageCorte "Borda de seguranca da chapa (mm)" 288 26 260 20
            pageCorte.Controls.Add lbGap
            pageCorte.Controls.Add lbBorda
            txtGap = addText pageCorte "5" 18 50 150 24
            txtBorda = addText pageCorte "15" 288 50 150 24

            local lbAlign = addLabel pageCorte "Alinhamento / veio da madeira" 18 104 260 20
            local lbGroup = addLabel pageCorte "Estrategia de alinhamento e corte" 18 170 290 20
            pageCorte.Controls.Add lbAlign
            pageCorte.Controls.Add lbGroup
            cmbAlign = addCombo pageCorte 18 128 430 24
            fillCombo cmbAlign #("Rotacao Livre (Melhor Sobra)", "Manter Orientacao Original", "Forcar Maior Lado na Horizontal") 1
            cmbGroup = addCombo pageCorte 18 194 430 24
            fillCombo cmbGroup #("Otimizacao Livre em Niveis", "Agrupar Tiras Horizontais (Mesma Altura)", "Agrupar Tiras Verticais (Mesma Largura)") 2

            addInfo pageCorte "Dica" "Agrupar tiras horizontais costuma gerar listas mais faceis para seccionadora.\nUse rotacao livre quando o veio nao for critico." 488 34 250 160
            -- BUG1: habilita digitacao numerica nos campos de gap/borda
            dotNet.addEventHandler txtGap   "GotFocus"  onFocusIn
            dotNet.addEventHandler txtGap   "LostFocus" onFocusOut
            dotNet.addEventHandler txtBorda "GotFocus"  onFocusIn
            dotNet.addEventHandler txtBorda "LostFocus" onFocusOut
        )

        fn buildMaoObra =
        (
            pageMaoObra = dotNetObject "System.Windows.Forms.TabPage" "Mao de Obra"
            tabs.TabPages.Add pageMaoObra

            local lbInfo = addLabel pageMaoObra \
                "Coeficientes para estimativa automatica de Mao de Obra (salvos em INI):" 18 16 700 20
            pageMaoObra.Controls.Add lbInfo

            -- Linhas: label | campo | descricao
            fn addCoefRow lbl val descr y tb =
            (
                local l1 = addLabel pageMaoObra lbl   18  (y+2) 190 18
                pageMaoObra.Controls.Add l1
                tb.Text     = substituteString (val as string) "," "."
                tb.Location = (dnPoint 215 y)
                tb.Size     = (dnSize 90 24)
                pageMaoObra.Controls.Add tb
                dotNet.addEventHandler tb "GotFocus"  onFocusIn
                dotNet.addEventHandler tb "LostFocus" onFocusOut
                local l2 = addLabel pageMaoObra descr 315 (y+2) 390 18
                pageMaoObra.Controls.Add l2
            )

            -- Cria TextBoxes e expoe em globais G_TxtMO* para que onAdvance
            -- possa ler os valores mesmo apos buildMaoObra retornar.
            txtMOBase   = dotNetObject "System.Windows.Forms.TextBox"; ::G_TxtMOBase   = txtMOBase
            txtMOKPeca  = dotNetObject "System.Windows.Forms.TextBox"; ::G_TxtMOKPeca  = txtMOKPeca
            txtMOKCorte = dotNetObject "System.Windows.Forms.TextBox"; ::G_TxtMOKCorte = txtMOKCorte
            txtMOKFita  = dotNetObject "System.Windows.Forms.TextBox"; ::G_TxtMOKFita  = txtMOKFita
            txtMOKFerr  = dotNetObject "System.Windows.Forms.TextBox"; ::G_TxtMOKFerr  = txtMOKFerr
            txtMOKPeso  = dotNetObject "System.Windows.Forms.TextBox"; ::G_TxtMOKPeso  = txtMOKPeso
            txtMODens   = dotNetObject "System.Windows.Forms.TextBox"; ::G_TxtMODens   = txtMODens
            txtMOKPerda = dotNetObject "System.Windows.Forms.TextBox"; ::G_TxtMOKPerda = txtMOKPerda

            addCoefRow "Base fixa (R$):"              ::G_MO_BasFixa          "Valor minimo por cotacao, independente do projeto"      48  txtMOBase
            addCoefRow "Por peca distinta (R$/peca):" ::G_MO_KPeca            "Cada peca diferente no plano de corte"                  80  txtMOKPeca
            addCoefRow "Por metro linear de corte:"   ::G_MO_KCorteM          "Soma comp+larg de cada peca (metros)"                  112  txtMOKCorte
            addCoefRow "Por metro de fita (R$/m):"    ::G_MO_KFita            "Metro de fita de borda aplicada"                       144  txtMOKFita
            addCoefRow "Por ferragem (R$/unid):"      ::G_MO_KFerragem        "Cada ferragem selecionada na lista"                    176  txtMOKFerr
            addCoefRow "Por kg estimado (R$/kg):"     ::G_MO_KPeso            "Peso calculado por volume x densidade"                 208  txtMOKPeso
            addCoefRow "Densidade madeira (kg/m3):"   ::G_MO_Densidade        "MDF=750 MDP=700 Pinus=530 — usado no calculo de peso"  240  txtMODens
            addCoefRow "Perda CNC (0.08–0.12):"       ::G_MO_KPerdaSeguranca  "Fator de perda de serragem/refile aplicado ao CMC_Chapas" 272 txtMOKPerda

            -- BUG2 fix: sincroniza globais G_MO_* ao sair de cada campo.
            -- Usa G_TxtMO* (globais) para garantir acesso correto ao valor editado.
            fn onMOLeave s a =
            (
                local pf v
                if ::G_TxtMOBase   != undefined do ( pf = substituteString ::G_TxtMOBase.Text   "," "."; v = 50.0;  try (v = pf as float) catch(); ::G_MO_BasFixa         = v )
                if ::G_TxtMOKPeca  != undefined do ( pf = substituteString ::G_TxtMOKPeca.Text  "," "."; v = 2.5;   try (v = pf as float) catch(); ::G_MO_KPeca           = v )
                if ::G_TxtMOKCorte != undefined do ( pf = substituteString ::G_TxtMOKCorte.Text "," "."; v = 0.8;   try (v = pf as float) catch(); ::G_MO_KCorteM         = v )
                if ::G_TxtMOKFita  != undefined do ( pf = substituteString ::G_TxtMOKFita.Text  "," "."; v = 0.3;   try (v = pf as float) catch(); ::G_MO_KFita           = v )
                if ::G_TxtMOKFerr  != undefined do ( pf = substituteString ::G_TxtMOKFerr.Text  "," "."; v = 5.0;   try (v = pf as float) catch(); ::G_MO_KFerragem       = v )
                if ::G_TxtMOKPeso  != undefined do ( pf = substituteString ::G_TxtMOKPeso.Text  "," "."; v = 0.2;   try (v = pf as float) catch(); ::G_MO_KPeso           = v )
                if ::G_TxtMODens   != undefined do ( pf = substituteString ::G_TxtMODens.Text   "," "."; v = 700.0; try (v = pf as float) catch(); ::G_MO_Densidade       = v )
                if ::G_TxtMOKPerda != undefined do ( pf = substituteString ::G_TxtMOKPerda.Text "," "."; v = 0.10;  try (v = pf as float) catch(); ::G_MO_KPerdaSeguranca = v )
                try ( ::saveMOConfig() ) catch()
            )
            for tb in #(txtMOBase, txtMOKPeca, txtMOKCorte, txtMOKFita, \
                        txtMOKFerr, txtMOKPeso, txtMODens, txtMOKPerda) do
                dotNet.addEventHandler tb "Leave" onMOLeave

            local lbNote = addLabel pageMaoObra \
                "Nota: estes valores sao um pre-calculo orientativo. Em rlCusto voce pode substituir manualmente." \
                18 278 700 34
            lbNote.AutoSize = false
            try ( lbNote.ForeColor = (dotNetClass "System.Drawing.Color").FromArgb 100 100 120 ) catch()
            pageMaoObra.Controls.Add lbNote
        )

        fn buildStatus =
        (
            pageStatus = dotNetObject "System.Windows.Forms.TabPage" "Status"
            tabs.TabPages.Add pageStatus
            lblApi = addLabel pageStatus (if G_ApiOnline then "API Banco de Dados: Conectada" else "API Banco de Dados: Offline") 18 28 360 24
            pageStatus.Controls.Add lblApi
            addInfo pageStatus "Integracao" "Quando a API estiver online, as proximas telas permitem buscar chapas e fitas no banco por fornecedor, categoria, espessura e nome." 18 70 520 120
            addInfo pageStatus "Saidas" "O script pode exportar PDF/DWG, gerar cotacao e criar planilha com os custos do projeto." 18 202 520 100
        )

        on rlConfig open do
        (
            try ( ::loadMOConfig() ) catch()   -- garante valores mais recentes do INI
            tabs.TabPages.Clear()
            buildProjeto()
            buildCorte()
            buildMaoObra()
            buildStatus()
            btnAvan.Text    = "Avancar para Fitas"
            btnCancel.Text  = "Ver Cotacoes"
            lbFooter.Text   = if G_ApiOnline then "API online: busca de precos habilitada" else "API offline: precos manuais"
            try ( ::aplicarTemaForm lbFooter.FindForm() ) catch()
            polishMainUi()
        )

        on btnAvan Click sender args do onAdvance sender args
        on btnCancel Click sender args do onCancel sender args
    )

    createDialog rlConfig style:#(#style_titlebar, #style_border, #style_sysmenu) bgcolor:(color 245 246 248)
)
-- ============================================================
-- BUSCA DE CLIENTES: modal para selecionar cliente existente
-- ============================================================
fn abrirBuscaClienteAPI =
(
    G_TempSearchResults = #()

    rollout rlBuscaCliente "Selecionar Cliente" width:700 height:480
    (
        dotNetControl lbNome   "System.Windows.Forms.Label"   pos:[12,12]  width:90  height:18
        dotNetControl txtNome  "System.Windows.Forms.TextBox" pos:[12,32]  width:480 height:24
        dotNetControl btnSearch "System.Windows.Forms.Button" pos:[504,30] width:180 height:28
        dotNetControl grid     "System.Windows.Forms.DataGridView" pos:[12,68] width:670 height:300
        dotNetControl lbStatus "System.Windows.Forms.Label"   pos:[12,376] width:670 height:18
        dotNetControl btnUsar  "System.Windows.Forms.Button"  pos:[438,406] width:244 height:28
        dotNetControl btnNovo  "System.Windows.Forms.Button"  pos:[244,406] width:186 height:28
        dotNetControl btnCancel "System.Windows.Forms.Button" pos:[12,406]  width:120 height:28
        dotNetControl lbLoad   "System.Windows.Forms.Label"       pos:[12,440] width:670 height:16

        fn dnColText name header width readOnly:true =
        (
            local col = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"
            col.Name = name; col.HeaderText = header; col.Width = width; col.ReadOnly = readOnly; col
        )

        fn setupGrid =
        (
            grid.AllowUserToAddRows = false; grid.AllowUserToDeleteRows = false
            grid.RowHeadersVisible = false;  grid.MultiSelect = false
            grid.ReadOnly = true
            grid.SelectionMode = (dotNetClass "System.Windows.Forms.DataGridViewSelectionMode").FullRowSelect
            grid.Columns.Clear()
            grid.Columns.Add (dnColText "nome"      "Nome"      240)
            grid.Columns.Add (dnColText "documento" "Documento" 140)
            grid.Columns.Add (dnColText "cidade"    "Cidade"    120)
            grid.Columns.Add (dnColText "uf"        "UF"         40)
            grid.Columns.Add (dnColText "telefone"  "Telefone"  110)
        )

        fn selectedIdx =
        (
            local idx = 0
            try ( if grid.SelectedRows.Count > 0 do idx = grid.SelectedRows.Item[0].Index + 1 ) catch (idx = 0)
            idx
        )

        fn populateGrid =
        (
            grid.Rows.Clear()
            for it in G_TempSearchResults do
            (
                local rowIdx = grid.Rows.Add()
                local row    = grid.Rows.Item[rowIdx]
                row.Cells.Item[0].Value = it[2]
                row.Cells.Item[1].Value = it[3]
                row.Cells.Item[2].Value = it[7]
                row.Cells.Item[3].Value = it[8]
                row.Cells.Item[4].Value = it[4]
            )
        )

        fn doSearch =
        (
            lbStatus.Text = "Pesquisando..."
            grid.Rows.Clear()
            lbLoad.Text    = "|"
            lbLoad.Visible = true
            G_ActiveSpinner = lbLoad
            btnSearch.Enabled = false
            windows.processPostedMessages()
            G_TempSearchResults = ::apiSearchClientes txtNome.Text
            populateGrid()
            G_ActiveSpinner = undefined
            lbLoad.Visible  = false
            btnSearch.Enabled = true
            lbStatus.Text = (G_TempSearchResults.count as string) + " cliente(s) encontrado(s)"
        )

        fn usarSelecionado =
        (
            local idx = selectedIdx()
            if idx >= 1 and idx <= G_TempSearchResults.count do
            (
                local it = G_TempSearchResults[idx]
                G_ClienteSelecionadoId   = it[1]
                G_ClienteSelecionadoNome = it[2]
                destroyDialog rlBuscaCliente
                try (::G_ActiveDadosClienteDlg.atualizarClienteSel()) catch()
            )
        )

        on rlBuscaCliente open do
        (
            lbNome.Text     = "Buscar por nome:"
            btnSearch.Text  = "Pesquisar"
            btnUsar.Text    = "Selecionar"
            btnNovo.Text    = "Cadastrar Novo Cliente"
            btnCancel.Text  = "← Voltar"
            lbLoad.Visible  = false
            setupGrid()
            try ( ::aplicarTemaForm lbLoad.FindForm() ) catch()
            lbStatus.Text = "Digite um nome e clique em Pesquisar."
        )

        on txtNome GotFocus  sender args do ( enableAccelerators = false )
        on txtNome LostFocus sender args do ( enableAccelerators = true  )
        on btnSearch Click sender args do doSearch()
        on grid CellDoubleClick sender args do usarSelecionado()
        on btnUsar Click sender args do usarSelecionado()
        on btnNovo Click sender args do
        (
            destroyDialog rlBuscaCliente
            try ( ::abrirCadastroCliente() ) catch()
        )
        on btnCancel Click sender args do destroyDialog rlBuscaCliente
    )

    createDialog rlBuscaCliente style:#(#style_titlebar, #style_border, #style_sysmenu) bgcolor:(color 245 246 248)
)

-- ============================================================
-- MODAL CADASTRO DE NOVO CLIENTE (dialog dedicado e focado)
-- ============================================================
fn abrirCadastroCliente =
(
rollout rlCadastroCliente "Cadastrar Novo Cliente" width:480 height:310
(
    -- Nome
    dotNetControl lbNome  "System.Windows.Forms.Label"   pos:[12,14]  width:456 height:16
    dotNetControl txtNome "System.Windows.Forms.TextBox" pos:[12,32]  width:456 height:26

    -- Documento + Telefone
    dotNetControl lbDoc   "System.Windows.Forms.Label"   pos:[12,70]  width:200 height:16
    dotNetControl lbTel   "System.Windows.Forms.Label"   pos:[244,70] width:120 height:16
    dotNetControl txtDoc  "System.Windows.Forms.TextBox" pos:[12,88]  width:220 height:26
    dotNetControl txtTel  "System.Windows.Forms.TextBox" pos:[244,88] width:224 height:26

    -- Email + Cidade + UF
    dotNetControl lbEmail "System.Windows.Forms.Label"   pos:[12,126] width:140 height:16
    dotNetControl lbCid   "System.Windows.Forms.Label"   pos:[250,126] width:140 height:16
    dotNetControl lbUF    "System.Windows.Forms.Label"   pos:[432,126] width:36  height:16
    dotNetControl txtEmail "System.Windows.Forms.TextBox" pos:[12,144]  width:226 height:26
    dotNetControl txtCid  "System.Windows.Forms.TextBox" pos:[250,144] width:170 height:26
    dotNetControl txtUF   "System.Windows.Forms.TextBox" pos:[432,144] width:36  height:26

    -- Status
    dotNetControl lbStatus "System.Windows.Forms.Label"  pos:[12,182] width:456 height:36

    -- Botoes
    dotNetControl btnCancel "System.Windows.Forms.Button" pos:[12,228]  width:130 height:34
    dotNetControl btnSalvar "System.Windows.Forms.Button" pos:[316,228] width:152 height:34

    on rlCadastroCliente open do
    (
        try ( ::aplicarTemaForm lbNome.FindForm() ) catch()
        lbNome.Text    = "Nome completo *"
        lbDoc.Text     = "CPF / CNPJ"
        lbTel.Text     = "Telefone"
        lbEmail.Text   = "E-mail"
        lbCid.Text     = "Cidade"
        lbUF.Text      = "UF"
        btnCancel.Text = "← Voltar"
        btnSalvar.Text = "Salvar Cliente"
        lbStatus.Text  = ""
        lbStatus.ForeColor = (dotNetClass "System.Drawing.Color").Red
        -- Destaca botao principal
        local corOK = (dotNetClass "System.Drawing.Color").FromArgb 46 139 87
        try ( btnSalvar.UseVisualStyleBackColor = false ) catch()
        btnSalvar.BackColor = corOK
        btnSalvar.ForeColor = (dotNetClass "System.Drawing.Color").White
    )

    on btnSalvar Click sender args do
    (
        local nome = txtNome.Text
        local doc  = txtDoc.Text
        if nome == "" do
        (
            lbStatus.ForeColor = (dotNetClass "System.Drawing.Color").Red
            lbStatus.Text = "Nome e obrigatorio."
            return undefined
        )
        if doc != "" and not (::validarDocumento doc) do
        (
            lbStatus.ForeColor = (dotNetClass "System.Drawing.Color").Red
            lbStatus.Text = "CPF/CNPJ invalido. Verifique os digitos."
            return undefined
        )
        local docFmt = if doc != "" then (::formatarDocumento doc) else ""
        lbStatus.ForeColor = (dotNetClass "System.Drawing.Color").FromArgb 80 80 80
        lbStatus.Text = "Salvando..."
        windows.processPostedMessages()
        local res = ::apiCreateCliente nome docFmt (txtTel.Text) (txtEmail.Text) \
                        "" (txtCid.Text) (txtUF.Text) ""
        if res[1] then
        (
            ::G_ClienteSelecionadoId   = res[2]
            ::G_ClienteSelecionadoNome = nome
            destroyDialog rlCadastroCliente
            -- Atualiza o painel de cliente em rlDadosCliente se estiver aberto
            try ( ::G_ActiveDadosClienteDlg.atualizarClienteSel() ) catch()
        )
        else
        (
            lbStatus.ForeColor = (dotNetClass "System.Drawing.Color").Red
            lbStatus.Text = "Erro ao salvar: " + res[3]
        )
    )

    on btnCancel Click sender args do destroyDialog rlCadastroCliente

    on txtNome  GotFocus sender args do ( enableAccelerators = false )
    on txtNome  LostFocus sender args do ( enableAccelerators = true  )
    on txtDoc   GotFocus sender args do ( enableAccelerators = false )
    on txtDoc   LostFocus sender args do ( enableAccelerators = true  )
    on txtTel   GotFocus sender args do ( enableAccelerators = false )
    on txtTel   LostFocus sender args do ( enableAccelerators = true  )
    on txtEmail GotFocus sender args do ( enableAccelerators = false )
    on txtEmail LostFocus sender args do ( enableAccelerators = true  )
    on txtCid   GotFocus sender args do ( enableAccelerators = false )
    on txtCid   LostFocus sender args do ( enableAccelerators = true  )
    on txtUF    GotFocus sender args do ( enableAccelerators = false )
    on txtUF    LostFocus sender args do ( enableAccelerators = true  )
)
    createDialog rlCadastroCliente style:#(#style_titlebar, #style_border, #style_sysmenu) bgcolor:(color 245 246 248)
)

-- ============================================================
-- MODAL DADOS DO CLIENTE / PROJETO — redesenhado
-- ============================================================
fn abrirDadosCliente =
(
rollout rlDadosCliente "Cotacao — Cliente e Projeto" width:520 height:456
(
    -- ── CLIENTE ──────────────────────────────────────────────
    dotNetControl lbSecCliente   "System.Windows.Forms.Label"  pos:[12, 8]  width:100 height:18
    dotNetControl sepCliente     "System.Windows.Forms.Label"  pos:[118,16] width:390 height:2

    dotNetControl lbCliLabel     "System.Windows.Forms.Label"  pos:[12,34]  width:200 height:16
    dotNetControl lbClienteSel   "System.Windows.Forms.Label"  pos:[12,52]  width:496 height:26

    dotNetControl btnBuscarCli   "System.Windows.Forms.Button" pos:[12,86]  width:220 height:30
    dotNetControl btnNovoCli     "System.Windows.Forms.Button" pos:[244,86] width:264 height:30

    -- ── PROJETO ──────────────────────────────────────────────
    dotNetControl lbSecProjeto   "System.Windows.Forms.Label"  pos:[12,132] width:100 height:18
    dotNetControl sepProjeto     "System.Windows.Forms.Label"  pos:[118,140] width:390 height:2

    dotNetControl lbProjeto      "System.Windows.Forms.Label"  pos:[12,158] width:496 height:16
    dotNetControl txtProjeto     "System.Windows.Forms.TextBox" pos:[12,176] width:496 height:26

    dotNetControl lbEntrega      "System.Windows.Forms.Label"  pos:[12,212]  width:220 height:16
    dotNetControl lbDesconto     "System.Windows.Forms.Label"  pos:[248,212] width:160 height:16
    dotNetControl txtEntrega     "System.Windows.Forms.TextBox" pos:[12,230]  width:200 height:26
    dotNetControl txtDesconto    "System.Windows.Forms.TextBox" pos:[248,230] width:80  height:26

    dotNetControl lbObs          "System.Windows.Forms.Label"  pos:[12,268] width:496 height:16
    dotNetControl txtObs         "System.Windows.Forms.TextBox" pos:[12,286] width:496 height:68

    -- Status + botoes
    dotNetControl lbValidacao    "System.Windows.Forms.Label"  pos:[12,364] width:496 height:36
    dotNetControl btnCancelar    "System.Windows.Forms.Button" pos:[12,408]  width:140 height:36
    dotNetControl btnConfirmar   "System.Windows.Forms.Button" pos:[268,408] width:240 height:36

    fn atualizarClienteSel =
    (
        if ::G_ClienteSelecionadoId > 0 then
        (
            lbClienteSel.Text      = "  " + ::G_ClienteSelecionadoNome
            lbClienteSel.ForeColor = (dotNetClass "System.Drawing.Color").FromArgb 30 110 30
            lbClienteSel.BackColor = (dotNetClass "System.Drawing.Color").FromArgb 225 245 225
        )
        else
        (
            lbClienteSel.Text      = "  Nenhum cliente selecionado"
            lbClienteSel.ForeColor = (dotNetClass "System.Drawing.Color").FromArgb 140 80 0
            lbClienteSel.BackColor = (dotNetClass "System.Drawing.Color").FromArgb 255 245 220
        )
    )

    on rlDadosCliente open do
    (
        try ( ::aplicarTemaForm lbSecCliente.FindForm() ) catch()

        -- Fontes de secao
        local fntBold = dotNetObject "System.Drawing.Font" "Segoe UI" 9.0 \
                            ((dotNetClass "System.Drawing.FontStyle").Bold)
        lbSecCliente.Text  = "CLIENTE"
        lbSecCliente.Font  = fntBold
        lbSecProjeto.Text  = "PROJETO"
        lbSecProjeto.Font  = fntBold

        -- Separadores visuais (linha horizontal)
        local corSep = (dotNetClass "System.Drawing.Color").FromArgb 180 180 185
        sepCliente.BackColor  = corSep
        sepProjeto.BackColor  = corSep

        -- Labels
        lbCliLabel.Text    = "Cliente selecionado:"
        lbProjeto.Text     = "Nome do Projeto  *"
        lbEntrega.Text     = "Previsao de Entrega"
        lbDesconto.Text    = "Desconto Global (%)"
        lbObs.Text         = "Observacoes (opcional)"

        -- Botoes
        btnBuscarCli.Text  = "Buscar Cliente Existente"
        btnNovoCli.Text    = "Cadastrar Novo Cliente"
        btnCancelar.Text   = "← Voltar"
        btnConfirmar.Text  = "Confirmar e Gerar Planilha"

        -- Campos
        txtObs.Multiline  = true
        txtObs.ScrollBars = (dotNetClass "System.Windows.Forms.ScrollBars").Vertical
        txtDesconto.Text  = "0"
        txtEntrega.Text   = ""

        -- Destaca botao confirmar
        local corOK = (dotNetClass "System.Drawing.Color").FromArgb 46 139 87
        try ( btnConfirmar.UseVisualStyleBackColor = false ) catch()
        btnConfirmar.BackColor = corOK
        btnConfirmar.ForeColor = (dotNetClass "System.Drawing.Color").White

        lbValidacao.Text      = ""
        lbValidacao.ForeColor = (dotNetClass "System.Drawing.Color").Red

        atualizarClienteSel()
    )

    on btnBuscarCli  Click sender args do ::abrirBuscaClienteAPI()
    on btnNovoCli    Click sender args do ::abrirCadastroCliente()

    on btnConfirmar Click sender args do
    (
        if ::G_ClienteSelecionadoId <= 0 do
        (
            lbValidacao.ForeColor = (dotNetClass "System.Drawing.Color").Red
            lbValidacao.Text = "Selecione ou cadastre um cliente antes de confirmar."
            return undefined
        )
        if txtProjeto.Text == "" do
        (
            lbValidacao.ForeColor = (dotNetClass "System.Drawing.Color").Red
            lbValidacao.Text = "Nome do Projeto e obrigatorio."
            return undefined
        )
        local desconto = try (txtDesconto.Text as float) catch 0.0
        if desconto < 0 or desconto > 100 do
        (
            lbValidacao.ForeColor = (dotNetClass "System.Drawing.Color").Red
            lbValidacao.Text = "Desconto deve ser entre 0 e 100 (ex: 10 para 10%)."
            return undefined
        )
        ::G_DadosCotacaoCliente = #(
            ::G_ClienteSelecionadoId,
            txtProjeto.Text,
            txtObs.Text,
            txtEntrega.Text,
            desconto
        )
        destroyDialog rlDadosCliente
        try ( ::G_ActiveCustoRl.finalizarCotacao() ) catch (format "Erro finalizarCotacao: %\n" (getCurrentException()))
    )

    on btnCancelar Click sender args do
    (
        ::G_DadosCotacaoCliente = #()
        destroyDialog rlDadosCliente
    )

    on txtProjeto  GotFocus sender args do ( enableAccelerators = false )
    on txtProjeto  LostFocus sender args do ( enableAccelerators = true  )
    on txtEntrega  GotFocus sender args do ( enableAccelerators = false )
    on txtEntrega  LostFocus sender args do ( enableAccelerators = true  )
    on txtDesconto GotFocus sender args do ( enableAccelerators = false )
    on txtDesconto LostFocus sender args do ( enableAccelerators = true  )
    on txtObs      GotFocus sender args do ( enableAccelerators = false )
    on txtObs      LostFocus sender args do ( enableAccelerators = true  )
)
    G_ActiveDadosClienteDlg = rlDadosCliente
    createDialog rlDadosCliente style:#(#style_titlebar, #style_border, #style_sysmenu) bgcolor:(color 245 246 248)
)

-- ============================================================
-- FEATURE 2 (BUG3): Modal de selecao de cliente para filtrar cotacoes
-- ============================================================
fn abrirFiltroClienteCotacoes =
(
    G_FCliResults = #()

    rollout rlFiltroCliente "Selecionar Cliente — Filtro" width:640 height:456
    (
        dotNetControl lbBusca  "System.Windows.Forms.Label"        pos:[12,12]  width:90  height:18
        dotNetControl txtBusca "System.Windows.Forms.TextBox"      pos:[12,32]  width:460 height:24
        dotNetControl btnBuscar "System.Windows.Forms.Button"      pos:[480,30] width:148 height:28
        dotNetControl grid     "System.Windows.Forms.DataGridView" pos:[12,68]  width:616 height:298
        dotNetControl lbStatus "System.Windows.Forms.Label"        pos:[12,374] width:616 height:18
        dotNetControl btnTodos  "System.Windows.Forms.Button"      pos:[12,404]  width:140 height:30
        dotNetControl btnVoltar "System.Windows.Forms.Button"      pos:[160,404] width:120 height:30
        dotNetControl btnSelec  "System.Windows.Forms.Button"      pos:[396,404] width:232 height:30

        fn dnC nm hd wd = (
            local c = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"
            c.Name = nm; c.HeaderText = hd; c.Width = wd; c.ReadOnly = true; c
        )

        fn setupGrid =
        (
            grid.AllowUserToAddRows    = false
            grid.AllowUserToDeleteRows = false
            grid.RowHeadersVisible     = false
            grid.MultiSelect           = false
            grid.ReadOnly              = true
            grid.SelectionMode = (dotNetClass "System.Windows.Forms.DataGridViewSelectionMode").FullRowSelect
            grid.Columns.Clear()
            grid.Columns.Add (dnC "nome" "Nome"       240)
            grid.Columns.Add (dnC "doc"  "Documento"  140)
            grid.Columns.Add (dnC "cid"  "Cidade"     120)
            grid.Columns.Add (dnC "uf"   "UF"          40)
            grid.Columns.Add (dnC "tel"  "Telefone"    68)
        )

        fn populateGrid =
        (
            -- BUG1 fix: grid pode ter backing-object null (dotNetControl modeless).
            -- Se null, tenta re-inicializar antes de popular; falha silenciosamente.
            try ( if grid.Handle == (dotNetObject "System.IntPtr" 0) do setupGrid() ) catch()
            try ( grid.Rows.Clear() ) catch ( lbStatus.Text = "Erro ao inicializar lista."; return undefined )
            for it in ::G_FCliResults do
            (
                local ri = try ( grid.Rows.Add() ) catch -1
                if ri < 0 do continue
                local rw = grid.Rows.Item[ri]
                rw.Cells.Item[0].Value = it[2]
                rw.Cells.Item[1].Value = it[3]
                rw.Cells.Item[2].Value = it[7]
                rw.Cells.Item[3].Value = it[8]
                rw.Cells.Item[4].Value = it[4]
            )
        )

        fn doSearch =
        (
            lbStatus.Text = "Pesquisando..."
            ::G_FCliResults = ::apiSearchClientes txtBusca.Text
            populateGrid()
            lbStatus.Text = (::G_FCliResults.count as string) + " cliente(s) encontrado(s)"
        )

        fn selecionarItem =
        (
            local idx = 0
            try ( if grid.SelectedRows.Count > 0 do idx = grid.SelectedRows.Item[0].Index + 1 ) catch()
            if idx >= 1 and idx <= ::G_FCliResults.count do
            (
                local it = ::G_FCliResults[idx]
                ::G_CotFiltroClienteId   = it[1]
                ::G_CotFiltroClienteNome = it[2]
                destroyDialog rlFiltroCliente
                try ( ::G_ActiveCotacoesRl.aplicarFiltroCliente() ) catch()
            )
        )

        on rlFiltroCliente open do
        (
            lbBusca.Text  = "Buscar por nome:"
            btnBuscar.Text = "Pesquisar"
            btnTodos.Text  = "Ver Todos"
            btnVoltar.Text = "← Voltar"
            btnSelec.Text  = "Selecionar Cliente"
            setupGrid()
            try ( ::aplicarTemaForm lbBusca.FindForm() ) catch()
            lbStatus.Text = "Digite um nome e clique em Pesquisar."
        )

        on txtBusca GotFocus  sender args do ( enableAccelerators = false )
        on txtBusca LostFocus sender args do ( enableAccelerators = true  )
        on btnBuscar Click sender args do doSearch()
        on grid CellDoubleClick sender args do selecionarItem()
        on btnSelec Click sender args do selecionarItem()
        on btnTodos Click sender args do
        (
            ::G_CotFiltroClienteId   = 0
            ::G_CotFiltroClienteNome = ""
            destroyDialog rlFiltroCliente
            try ( ::G_ActiveCotacoesRl.aplicarFiltroCliente() ) catch()
        )
        on btnVoltar Click sender args do destroyDialog rlFiltroCliente
    )

    createDialog rlFiltroCliente style:#(#style_titlebar, #style_border, #style_sysmenu) \
        bgcolor:(color 245 246 248)
)

-- ============================================================
-- FEATURE 2: Tela de Historico de Cotacoes
-- ============================================================
fn abrirCotacoes =
(
    -- Janela: 1100 x 820
    -- pnlLeft e tabCtrl declarados DIRETAMENTE no rollout (como todos os outros modais)
    -- para que o MaxScript gerencie o DPI scaling — nao via .NET API pos/size manual.
    rollout rlCotacoes "Historico de Cotacoes" width:1100 height:820
    (
        -- Coluna esquerda: filtros + lista (largura fixa 380px)
        dotNetControl pnlLeft      "System.Windows.Forms.Panel"      pos:[8,8]    width:380 height:762
        -- Area direita: abas de conteudo (largura = 1100-8-380-8-8 = 696px)
        dotNetControl tabCtrl      "System.Windows.Forms.TabControl" pos:[396,8]  width:696 height:762
        -- Loading overlay: cobre ambas as colunas durante chamadas API
        dotNetControl pnlLoad      "System.Windows.Forms.Panel"      pos:[8,8]    width:1084 height:762
        -- Rodape
        dotNetControl btnVoltar        "System.Windows.Forms.Button"  pos:[8,778]   width:130 height:26
        dotNetControl btnExportPDF     "System.Windows.Forms.Button"  pos:[148,778] width:170 height:26
        dotNetControl btnExportProposta "System.Windows.Forms.Button" pos:[328,778] width:210 height:26
        dotNetControl lbRodape         "System.Windows.Forms.Label"   pos:[548,782] width:490 height:18

        -- Variaveis da UI (preenchidas em buildUi)
        local gridCotacoes, lbClienteFiltro, btnSelectCli, btnLimparCli, txtDataIni, txtDataFim
        local btnPesquisar, lbResultado, lbSpinCot
        -- Resumo tab
        local lbCliNome, lbCliDoc, lbCliTel, lbCliEmail, lbCliCid
        local lbProjNome, lbProjEntrega, lbProjObs
        local lbFinCh, lbFinFt, lbFinOu, lbFinSub, lbFinDesc, lbFinTot
        local lbFinMO, lbFinCMC, lbFinCOB, lbFinMargem, lbFinPV, lbFinEfetivo, lbFinProduto
        -- Pecas tab
        local gridPecas
        -- Editar Pecas tab
        local gridEditPecas, lbPecasTotalM2, btnSalvarPecas, btnRestaurarPecas, lbPecasSalvStatus
        -- Editar tab — campos basicos
        local txtEditProj, txtEditEntrega, txtEditObs, txtEditDesc, btnSalvarEdit, lbSalvoStatus
        -- Editar tab — fitas, ferragens, outros
        local gridEditFitas, gridEditFerr
        local txtEditCola, txtEditMO, txtEditFrete
        local btnEditFitaBuscar, btnEditFitaAdd, btnEditFitaRemove
        local btnEditFerrBuscar, btnEditFerrRemove
        -- Cache local para edicao de ferragens
        local G_EditFerragensLista = #()  -- #(id, nome, valorUnit, fornecedor, qtd, subtotal)
        -- State
        local G_CotacoesLista = #()
        local G_CotId         = 0
        local G_CotDados      = undefined  -- ultimo #(cot, cli)

        fn dnPt x y = dotNetObject "System.Drawing.Point" x y
        fn dnSz w h = dotNetObject "System.Drawing.Size"  w h

        fn addLbl par txt x y w h =
        (
            local c = dotNetObject "System.Windows.Forms.Label"
            c.Text = txt; c.Location = dnPt x y; c.Size = dnSz w h
            par.Controls.Add c; c
        )
        fn addTxt par x y w h multiline:false =
        (
            local c = dotNetObject "System.Windows.Forms.TextBox"
            c.Location = dnPt x y; c.Size = dnSz w h
            c.Multiline = multiline
            par.Controls.Add c; c
        )
        fn addDate par x y w h =
        (
            local c = dotNetObject "System.Windows.Forms.DateTimePicker"
            c.Location = dnPt x y; c.Size = dnSz w h
            c.Format = (dotNetClass "System.Windows.Forms.DateTimePickerFormat").Short
            c.ShowCheckBox = true; c.Checked = false
            par.Controls.Add c; c
        )
        fn addBtn par txt x y w h =
        (
            local c = dotNetObject "System.Windows.Forms.Button"
            c.Text = txt; c.Location = dnPt x y; c.Size = dnSz w h
            par.Controls.Add c; c
        )
        fn addGrp par txt x y w h =
        (
            local c = dotNetObject "System.Windows.Forms.GroupBox"
            c.Text = txt; c.Location = dnPt x y; c.Size = dnSz w h
            par.Controls.Add c; c
        )
        fn makeDGVCol nm hd wd =
        (
            local col = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"
            col.Name = nm; col.HeaderText = hd; col.Width = wd; col.ReadOnly = true; col
        )

        -- ── styleGrid: aplica visual consistente (respiro, zebra, header, selecao) ──
        fn styleGrid g fillCols:false =
        (
            try (
                local clr = dotNetClass "System.Drawing.Color"
                g.BackgroundColor           = clr.White
                g.BorderStyle               = (dotNetClass "System.Windows.Forms.BorderStyle").FixedSingle
                g.CellBorderStyle           = (dotNetClass "System.Windows.Forms.DataGridViewCellBorderStyle").SingleHorizontal
                g.GridColor                 = (clr.FromArgb 228 232 238)
                g.RowHeadersVisible         = false
                g.AllowUserToResizeRows     = false
                g.AllowUserToResizeColumns  = true
                g.EnableHeadersVisualStyles = false
                -- Cabecalho
                g.ColumnHeadersHeight       = 34
                g.ColumnHeadersBorderStyle  = (dotNetClass "System.Windows.Forms.DataGridViewHeaderBorderStyle").Single
                g.ColumnHeadersDefaultCellStyle.BackColor = (clr.FromArgb 238 241 245)
                g.ColumnHeadersDefaultCellStyle.ForeColor = (clr.FromArgb 38 46 58)
                g.ColumnHeadersDefaultCellStyle.Font = dotNetObject "System.Drawing.Font" "Segoe UI" 9.0 \
                    ((dotNetClass "System.Drawing.FontStyle").Bold)
                g.ColumnHeadersDefaultCellStyle.Padding = (dotNetObject "System.Windows.Forms.Padding" 6 0 6 0)
                -- Linhas: altura + respiro interno
                g.RowTemplate.Height        = 28
                g.DefaultCellStyle.Padding  = (dotNetObject "System.Windows.Forms.Padding" 6 2 6 2)
                g.DefaultCellStyle.SelectionBackColor = (clr.FromArgb 26 115 232)
                g.DefaultCellStyle.SelectionForeColor = clr.White
                g.AlternatingRowsDefaultCellStyle.BackColor = (clr.FromArgb 247 249 251)
                g.Font = dotNetObject "System.Drawing.Font" "Segoe UI" 9.0
                if fillCols do
                    g.AutoSizeColumnsMode = (dotNetClass "System.Windows.Forms.DataGridViewAutoSizeColumnsMode").Fill
            ) catch()
        )

        fn fmtMoney v =
        (
            local s = substituteString (((floor(v * 100.0 + 0.5)) / 100.0) as string) "." ","
            "R$ " + s
        )
        fn fmtPct v = ((floor(v * 10 + 0.5)) / 10.0) as string + "%"

        -- ── Loading: spinner no rodape + botoes desabilitados ──
        fn showLoad =
        (
            try ( lbRodape.Text = "⏳  Consultando API, aguarde..." ) catch()
            try ( btnPesquisar.Enabled  = false ) catch()
            try ( btnVoltar.Enabled     = false ) catch()
            try ( btnExportPDF.Enabled  = false ) catch()
            windows.processPostedMessages()
        )
        fn hideLoad =
        (
            try ( lbRodape.Text = "" ) catch()
            try ( btnPesquisar.Enabled  = true ) catch()
            try ( btnVoltar.Enabled     = true ) catch()
            try ( btnExportPDF.Enabled  = true ) catch()
        )

        -- ── Limpa painel direito ──
        fn clearDetail =
        (
            try ( lbCliNome.Text     = "—" ) catch()
            try ( lbCliDoc.Text      = "—" ) catch()
            try ( lbCliTel.Text      = "—" ) catch()
            try ( lbCliEmail.Text    = "—" ) catch()
            try ( lbCliCid.Text      = "—" ) catch()
            try ( lbProjNome.Text    = "—" ) catch()
            try ( lbProjEntrega.Text = "—" ) catch()
            try ( lbProjObs.Text     = "" ) catch()
            try ( lbFinCh.Text       = "" ) catch()
            try ( lbFinFt.Text       = "" ) catch()
            try ( lbFinOu.Text       = "" ) catch()
            try ( lbFinSub.Text      = "" ) catch()
            try ( lbFinDesc.Text     = "" ) catch()
            try ( lbFinTot.Text      = "Selecione uma cotacao" ) catch()
            try ( lbFinMO.Text       = "" ) catch()
            try ( lbFinCMC.Text      = "" ) catch()
            try ( lbFinCOB.Text      = "" ) catch()
            try ( lbFinMargem.Text   = "" ) catch()
            try ( lbFinPV.Text       = "" ) catch()
            try ( lbFinEfetivo.Text  = "" ) catch()
            try ( lbFinProduto.Text  = "" ) catch()
            try ( gridPecas.Rows.Clear() ) catch()
            try ( gridEditPecas.Rows.Clear() ) catch()
            try ( lbPecasTotalM2.Text = "Total M² consumido: 0.0000 m²" ) catch()
            try ( lbPecasSalvStatus.Text = "" ) catch()
            try ( txtEditProj.Text    = "" ) catch()
            try ( txtEditEntrega.Text = "" ) catch()
            try ( txtEditObs.Text     = "" ) catch()
            try ( txtEditDesc.Text    = "0" ) catch()
            try ( lbSalvoStatus.Text  = "" ) catch()
            G_CotId    = 0
            G_CotDados = undefined
        )

        -- ── Popula aba Resumo ──
        fn populateResumo cot cli =
        (
            local cliNome  = if cli.count >= 1 then cli[1] else "Sem cliente"
            local cliDoc   = if cli.count >= 2 then cli[2] else ""
            local cliTel   = if cli.count >= 3 then cli[3] else ""
            local cliEmail = if cli.count >= 4 then cli[4] else ""
            local cliCid   = if cli.count >= 5 then (cli[5] + (if cli.count >= 6 and cli[6] != "" then (" - " + cli[6]) else "")) else ""
            try ( lbCliNome.Text  = cliNome ) catch()
            try ( lbCliDoc.Text   = if cliDoc   != "" then cliDoc   else "—" ) catch()
            try ( lbCliTel.Text   = if cliTel   != "" then cliTel   else "—" ) catch()
            try ( lbCliEmail.Text = if cliEmail != "" then cliEmail else "—" ) catch()
            try ( lbCliCid.Text   = if cliCid   != "" then cliCid   else "—" ) catch()

            local proj    = if cot.count >= 2 then cot[2] else ""
            local entrega = if cot.count >= 3 then cot[3] else ""
            local obs     = if cot.count >= 9 then cot[9] else ""
            try ( lbProjNome.Text    = if proj    != "" then proj    else "—" ) catch()
            try ( lbProjEntrega.Text = if entrega != "" then entrega else "—" ) catch()
            try ( lbProjObs.Text     = obs ) catch()

            local desc     = if cot.count >= 4  then cot[4]  else 0.0
            local totCh    = if cot.count >= 5  then cot[5]  else 0.0
            local totFt    = if cot.count >= 6  then cot[6]  else 0.0
            local totOu    = if cot.count >= 7  then cot[7]  else 0.0
            local subtotal = totCh + totFt + totOu
            local totFinal = subtotal * (1.0 - desc / 100.0)
            try ( lbFinCh.Text  = "Chapas:    " + (fmtMoney totCh)    ) catch()
            try ( lbFinFt.Text  = "Fita:      " + (fmtMoney totFt)    ) catch()
            try ( lbFinOu.Text  = "Outros:    " + (fmtMoney totOu)    ) catch()
            try ( lbFinSub.Text = "Subtotal:  " + (fmtMoney subtotal) ) catch()
            if desc > 0 then
                try ( lbFinDesc.Text = "Desconto:  -" + (fmtPct desc) + "  (" + (fmtMoney (subtotal - totFinal)) + ")" ) catch()
            else
                try ( lbFinDesc.Text = "" ) catch()
            try ( lbFinTot.Text = "TOTAL:     " + (fmtMoney totFinal) ) catch()
            -- MO — indice 20
            local maoObraVal = if cot.count >= 20 then (try (cot[20] as float) catch 0.0) else 0.0
            try ( lbFinMO.Text = if maoObraVal > 0.0 then ("MO: " + (fmtMoney maoObraVal)) else "" ) catch()

            -- Campos v9 CMC+Markup (indices 22–26); fallback para legacy se ausentes
            local caVal     = if cot.count >= 22 then (try (cot[22] as float) catch 0.0) else 0.0
            local cmcVal    = if cot.count >= 23 then (try (cot[23] as float) catch 0.0) else 0.0
            local cobVal    = if cot.count >= 24 then (try (cot[24] as float) catch 0.0) else 0.0
            local margemVal = if cot.count >= 25 then (try (cot[25] as float) catch 0.0) else 0.0
            local pvVal     = if cot.count >= 26 then (try (cot[26] as float) catch 0.0) else 0.0
            local impostoVal  = if cot.count >= 27 then (try (cot[27] as float) catch 0.0) else 0.0
            local comissaoVal = if cot.count >= 28 then (try (cot[28] as float) catch 0.0) else 0.0

            -- fallback para cotacoes antigas (pre-v9)
            if caVal  == 0.0 do caVal  = if cot.count >= 11 then (try (cot[11] as float) catch 0.0) else 0.0
            if cmcVal == 0.0 do cmcVal = if cot.count >= 16 then (try (cot[16] as float) catch 0.0) else 0.0

            local isV9 = cobVal > 0.0
            if isV9 then
            (
                try ( lbFinCMC.Text    = "CMC (mat. consumido): " + (fmtMoney cmcVal) ) catch()
                try ( lbFinCOB.Text    = "COB (operacional): "    + (fmtMoney cobVal) ) catch()
                local margemInt = (floor (margemVal + 0.5)) as integer
                local pctTotalV10 = margemVal + impostoVal + comissaoVal
                if pctTotalV10 > 95.0 do pctTotalV10 = 95.0
                try ( lbFinMargem.Text = "Margem: " + (margemInt as string) + "%" + \
                    (if impostoVal > 0.0 then (" + Imposto " + (((floor (impostoVal + 0.5)) as integer) as string) + "%") else "") + \
                    (if comissaoVal > 0.0 then (" + Comissao " + (((floor (comissaoVal + 0.5)) as integer) as string) + "%") else "") + \
                    " (por dentro do preco)" ) catch()
                try (
                    lbFinPV.Text = "PRECO DE VENDA: " + (fmtMoney (if pvVal > 0.0 then pvVal else (cobVal / (1.0 - pctTotalV10 / 100.0))))
                    local fntBold = dotNetObject "System.Drawing.Font" "Segoe UI" 9.5 \
                        ((dotNetClass "System.Drawing.FontStyle").Bold)
                    lbFinPV.Font = fntBold
                    lbFinPV.ForeColor = (dotNetClass "System.Drawing.Color").FromArgb 26 99 60
                ) catch()
                try ( lbFinEfetivo.Text = "CA (aquisicao ref.): " + (fmtMoney caVal) ) catch()
                try ( lbFinProduto.Text = "" ) catch()
            )
            else
            (
                -- cotacao legacy: mostra CA e CMC sem destaque de markup
                try ( lbFinCMC.Text    = if cmcVal > 0.0 then ("CMC: " + (fmtMoney cmcVal)) else "" ) catch()
                try ( lbFinCOB.Text    = "" ) catch()
                try ( lbFinMargem.Text = "" ) catch()
                try ( lbFinPV.Text     = "" ) catch()
                try ( lbFinEfetivo.Text = if caVal > 0.0 then ("Custo Aquisicao: " + (fmtMoney caVal)) else "" ) catch()
                try ( lbFinProduto.Text = "" ) catch()
            )
            try (
                local fntBig = dotNetObject "System.Drawing.Font" "Segoe UI" 11.0 \
                    ((dotNetClass "System.Drawing.FontStyle").Bold)
                lbFinTot.Font = fntBig
                lbFinTot.ForeColor = (dotNetClass "System.Drawing.Color").FromArgb 26 99 60
            ) catch()
        )

        -- ── Aba Editar Pecas: helpers ──
        -- Recalcula Área Unit e Área Total de uma linha do gridEditPecas
        fn recalcPecasRow rowIdx =
        (
            if gridEditPecas == undefined do return undefined
            local rw = try (gridEditPecas.Rows.Item[rowIdx]) catch undefined
            if rw == undefined do return undefined
            local cMm  = try (rw.Cells.Item[1].Value as float) catch 0.0
            local lMm  = try (rw.Cells.Item[2].Value as float) catch 0.0
            local qtd  = try (rw.Cells.Item[4].Value as integer) catch 1
            if qtd < 1 do qtd = 1
            local aUnit  = (cMm / 1000.0) * (lMm / 1000.0)
            local aTotal = aUnit * qtd
            try ( rw.Cells.Item[9].Value  = substituteString (((floor (aUnit  * 10000.0 + 0.5)) / 10000.0) as string) "," "." ) catch()
            try ( rw.Cells.Item[10].Value = substituteString (((floor (aTotal * 10000.0 + 0.5)) / 10000.0) as string) "," "." ) catch()
        )

        -- Recalcula e exibe total M² consumido
        fn recalcPecasTotal =
        (
            if gridEditPecas == undefined do return undefined
            local tot = 0.0
            for r = 0 to (gridEditPecas.Rows.Count - 1) do
            (
                local v = try (gridEditPecas.Rows.Item[r].Cells.Item[10].Value as float) catch 0.0
                tot += v
            )
            local totStr = substituteString (((floor (tot * 10000.0 + 0.5)) / 10000.0) as string) "," "."
            try ( lbPecasTotalM2.Text = "Total M² consumido: " + totStr + " m²" ) catch()
        )

        -- Serializa gridEditPecas de volta para JSON (mesmo formato de buildPecasJson)
        fn serializePecasGrid =
        (
            if gridEditPecas == undefined do return "[]"
            local ss = stringStream ""
            format "[" to:ss
            local nRows = gridEditPecas.Rows.Count
            local wrote = 0
            for r = 0 to (nRows - 1) do
            (
                local rw = gridEditPecas.Rows.Item[r]
                local nome  = try (rw.Cells.Item[0].Value as string) catch ""
                local cMm   = try (rw.Cells.Item[1].Value as float) catch 0.0
                local lMm   = try (rw.Cells.Item[2].Value as float) catch 0.0
                local espMm = try (rw.Cells.Item[3].Value as float) catch 0.0
                local qtd   = try (rw.Cells.Item[4].Value as integer) catch 1
                if qtd < 1 do qtd = 1
                local fitaC1 = try (rw.Cells.Item[5].Value as booleanClass) catch false
                local fitaC2 = try (rw.Cells.Item[6].Value as booleanClass) catch false
                local fitaL1 = try (rw.Cells.Item[7].Value as booleanClass) catch false
                local fitaL2 = try (rw.Cells.Item[8].Value as booleanClass) catch false
                local aUnit  = (cMm / 1000.0) * (lMm / 1000.0)
                local aTotal = aUnit * qtd
                local fitaM  = 0.0
                if fitaC1 do fitaM += cMm / 1000.0
                if fitaC2 do fitaM += cMm / 1000.0
                if fitaL1 do fitaM += lMm / 1000.0
                if fitaL2 do fitaM += lMm / 1000.0
                local nomeSafe = substituteString nome "\"" "'"
                if wrote > 0 do format "," to:ss
                format "{\"nome\":\"%\",\"comp_mm\":%,\"larg_mm\":%,\"esp_mm\":%,\"qtd\":%,\"area_m2\":%,\"fita_m\":%,\"fita_c1\":%,\"fita_c2\":%,\"fita_l1\":%,\"fita_l2\":%,\"preco_m2\":0,\"custo_unit\":0,\"custo_total\":0}" \
                    nomeSafe cMm lMm espMm qtd aUnit fitaM \
                    (if fitaC1 then "true" else "false") (if fitaC2 then "true" else "false") \
                    (if fitaL1 then "true" else "false") (if fitaL2 then "true" else "false") to:ss
                wrote += 1
            )
            format "]" to:ss
            ss as string
        )

        -- Popula o gridEditPecas a partir dos dados de apiGetCotacaoItems
        -- itensCache: resultado ja carregado (evita segunda chamada API quando
        -- populatePecas e populatePecasEdit sao chamadas em sequencia)
        fn populatePecasEdit itensCache:undefined =
        (
            if gridEditPecas == undefined do return undefined
            gridEditPecas.Rows.Clear()
            try ( lbPecasSalvStatus.Text = "" ) catch()
            if G_CotId <= 0 do return undefined
            local itens = if itensCache != undefined then itensCache else ::apiGetCotacaoItems G_CotId
            if itens == undefined do return undefined
            local pecas = if itens.count >= 5 then itens[5] else #()
            for pe in pecas do
            (
                -- pe = #(nome,compMm,largMm,espMm,qtd,areaM2,fitaM,precoM2,custoUnit,custoTotal,fitaC1,fitaC2,fitaL1,fitaL2)
                local ri = gridEditPecas.Rows.Add()
                local rw = gridEditPecas.Rows.Item[ri]
                local cMm   = pe[2]; local lMm  = pe[3]; local qtd = pe[5]
                local aUnit  = (cMm / 1000.0) * (lMm / 1000.0)
                local aTotal = aUnit * qtd
                rw.Cells.Item[0].Value  = pe[1]  -- nome
                rw.Cells.Item[1].Value  = substituteString (cMm as string) "," "."
                rw.Cells.Item[2].Value  = substituteString (lMm as string) "," "."
                rw.Cells.Item[3].Value  = substituteString (pe[4] as string) "," "."
                rw.Cells.Item[4].Value  = qtd as string
                rw.Cells.Item[5].Value  = if pe.count >= 11 then pe[11] else false  -- fita_c1
                rw.Cells.Item[6].Value  = if pe.count >= 12 then pe[12] else false  -- fita_c2
                rw.Cells.Item[7].Value  = if pe.count >= 13 then pe[13] else false  -- fita_l1
                rw.Cells.Item[8].Value  = if pe.count >= 14 then pe[14] else false  -- fita_l2
                rw.Cells.Item[9].Value  = substituteString (((floor (aUnit  * 10000.0 + 0.5)) / 10000.0) as string) "," "."
                rw.Cells.Item[10].Value = substituteString (((floor (aTotal * 10000.0 + 0.5)) / 10000.0) as string) "," "."
            )
            recalcPecasTotal()
        )

        -- ── Popula aba Pecas ──
        fn populatePecas itensCache:undefined =
        (
            if gridPecas == undefined do return undefined
            gridPecas.Rows.Clear()
            if G_CotId <= 0 do return undefined
            local itens = if itensCache != undefined then itensCache else ::apiGetCotacaoItems G_CotId
            if itens == undefined do return undefined
            local chapas    = itens[1]
            local fitas     = itens[2]
            local outros    = itens[3]
            local ferragens = if itens.count >= 4 then itens[4] else #()
            local pecas     = if itens.count >= 5 then itens[5] else #()

            fn addHeader grid txt colorR colorG colorB =
            (
                local hIdx = grid.Rows.Add()
                local hRow = grid.Rows.Item[hIdx]
                hRow.Cells.Item[0].Value = txt
                try ( hRow.DefaultCellStyle.BackColor = \
                          (dotNetClass "System.Drawing.Color").FromArgb colorR colorG colorB
                      hRow.DefaultCellStyle.Font = dotNetObject "System.Drawing.Font" "Segoe UI" 8.5 \
                          ((dotNetClass "System.Drawing.FontStyle").Bold) ) catch()
            )

            -- Pecas Planejadas (do plano de corte — custo por area, sem desperdicio)
            if pecas.count > 0 do
            (
                addHeader gridPecas ("▶ PECAS PLANEJADAS (" + (pecas.count as string) + ")") 200 240 220
                for pe in pecas do
                (
                    local ri = gridPecas.Rows.Add()
                    local rw = gridPecas.Rows.Item[ri]
                    -- pe = #(nome, compMm, largMm, espMm, qtd, areaM2, fitaM, precoM2, custoUnit, custoTotal)
                    local dimStr = (pe[2] as integer) as string + "x" + (pe[3] as integer) as string + \
                                   "x" + (pe[4] as integer) as string + " mm"
                    rw.Cells.Item[0].Value = pe[1]               -- nome
                    rw.Cells.Item[1].Value = dimStr              -- L x A x P
                    rw.Cells.Item[2].Value = pe[5] as string     -- qtd
                    rw.Cells.Item[3].Value = fmtMoney pe[9]     -- custo unit
                    rw.Cells.Item[4].Value = fmtMoney pe[10]    -- custo total
                )
            )

            -- Chapas
            if chapas.count > 0 do
            (
                addHeader gridPecas ("▶ CHAPAS (" + (chapas.count as string) + ")") 220 235 255
                for ch in chapas do
                (
                    local ri = gridPecas.Rows.Add()
                    local rw = gridPecas.Rows.Item[ri]
                    rw.Cells.Item[0].Value = ch[2]
                    rw.Cells.Item[1].Value = (ch[1] as string) + " mm"
                    rw.Cells.Item[2].Value = ch[3] as string
                    rw.Cells.Item[3].Value = fmtMoney ch[4]
                    rw.Cells.Item[4].Value = fmtMoney ch[5]
                )
            )

            -- Fitas
            if fitas.count > 0 do
            (
                addHeader gridPecas ("▶ FITAS DE BORDA (" + (fitas.count as string) + ")") 220 255 230
                for ft in fitas do
                (
                    local ri = gridPecas.Rows.Add()
                    local rw = gridPecas.Rows.Item[ri]
                    rw.Cells.Item[0].Value = ft[1]
                    rw.Cells.Item[1].Value = ""
                    rw.Cells.Item[2].Value = (ft[2] as string) + " m"
                    rw.Cells.Item[3].Value = fmtMoney ft[3]
                    rw.Cells.Item[4].Value = fmtMoney ft[4]
                )
            )

            -- Ferragens (novas)
            if ferragens.count > 0 do
            (
                addHeader gridPecas ("▶ FERRAGENS (" + (ferragens.count as string) + ")") 255 230 200
                for fe in ferragens do
                (
                    local ri = gridPecas.Rows.Add()
                    local rw = gridPecas.Rows.Item[ri]
                    -- fe = #(id, nome, valorUnit, fornecedor, qtd, subtotal)
                    rw.Cells.Item[0].Value = fe[2]                       -- nome
                    rw.Cells.Item[1].Value = fe[4]                       -- fornecedor
                    rw.Cells.Item[2].Value = fe[5] as string             -- qtd
                    rw.Cells.Item[3].Value = fmtMoney fe[3]              -- valor unit
                    rw.Cells.Item[4].Value = fmtMoney fe[6]              -- subtotal
                )
            )

            -- Outros custos
            if outros.count >= 4 and (outros[1] + outros[2] + outros[3] + outros[4]) > 0 do
            (
                addHeader gridPecas "▶ OUTROS CUSTOS" 255 245 210
                local outrosNomes = #("Ferragem (total)", "Cola", "Mao de Obra", "Frete")
                for i = 1 to 4 do if outros[i] > 0 do
                (
                    local ri = gridPecas.Rows.Add()
                    local rw = gridPecas.Rows.Item[ri]
                    rw.Cells.Item[0].Value = outrosNomes[i]
                    rw.Cells.Item[4].Value = fmtMoney outros[i]
                )
            )
        )

        -- ── refreshEditFitasGrid ──
        fn refreshEditFitasGrid fitasArr =
        (
            if gridEditFitas == undefined do return undefined
            gridEditFitas.Rows.Clear()
            for ft in fitasArr do
            (
                local ri = gridEditFitas.Rows.Add()
                local rw = gridEditFitas.Rows.Item[ri]
                rw.Cells.Item[0].Value = ft[1]             -- produto (RO)
                rw.Cells.Item[1].Value = ft[2] as string   -- metros
                rw.Cells.Item[2].Value = ft[3] as string   -- R$/m
                rw.Cells.Item[3].Value = fmtMoney ft[4]    -- subtotal (RO)
            )
        )

        -- ── refreshEditFerrGrid ──
        fn refreshEditFerrGrid =
        (
            if gridEditFerr == undefined do return undefined
            gridEditFerr.Rows.Clear()
            for fe in G_EditFerragensLista do
            (
                local ri = gridEditFerr.Rows.Add()
                local rw = gridEditFerr.Rows.Item[ri]
                rw.Cells.Item[0].Value = fe[2]             -- nome (RO)
                rw.Cells.Item[1].Value = fe[5] as string   -- qtd (editavel)
                rw.Cells.Item[2].Value = fmtMoney fe[3]    -- valor unit (RO)
                local sub = if fe.count >= 6 then fe[6] else (fe[3] * (try (fe[5] as integer) catch 1))
                rw.Cells.Item[3].Value = fmtMoney sub      -- subtotal (RO)
            )
        )

        -- ── recarregarFerrEdicao ──
        -- Chamada pelo callback de fechamento de rlBuscaFerragem (modeless).
        -- Normaliza tuplas (5→6 elementos com subtotal) e recarrega o grid de edicao.
        fn recarregarFerrEdicao =
        (
            local nova = #()
            for fe in ::G_FerragensLista do
            (
                local q   = try (fe[5] as integer) catch 1
                if q < 1 do q = 1
                local sub = if fe.count >= 6 then fe[6] else (fe[3] * q)
                append nova #(fe[1], fe[2], fe[3], fe[4], q, sub)
            )
            G_EditFerragensLista = nova
            refreshEditFerrGrid()
        )

        -- ── Popula aba Editar ──
        fn populateEditar cot =
        (
            local proj    = if cot.count >= 2  then cot[2]  else ""
            local entrega = if cot.count >= 3  then cot[3]  else ""
            local desc    = if cot.count >= 4  then cot[4]  else 0.0
            local obs     = if cot.count >= 9  then cot[9]  else ""
            try ( txtEditProj.Text    = if proj    != undefined then proj    else "" ) catch()
            try ( txtEditEntrega.Text = if entrega != undefined then entrega else "" ) catch()
            try ( txtEditObs.Text     = if obs     != undefined then obs     else "" ) catch()
            try ( txtEditDesc.Text    = desc as string ) catch()
            try ( lbSalvoStatus.Text  = "" ) catch()

            -- Carrega itens (fitas, ferragens, outros) para a grade de edicao
            if G_CotId > 0 do
            (
                local itens = ::apiGetCotacaoItems G_CotId
                if itens != undefined do
                (
                    local fitasArr = itens[2]
                    -- Converte fitas para formato G_FitasMultiLinhas-like
                    local fitasEdit = #()
                    for ft in fitasArr do
                        append fitasEdit #(ft[1], ft[2], ft[3], ft[4])
                    -- Se vazio, inicializa linha padrao
                    if fitasEdit.count == 0 do
                        fitasEdit = #(#("(sem fita)", 0.0, 0.0, 0.0))
                    refreshEditFitasGrid fitasEdit

                    -- Ferragens
                    G_EditFerragensLista = #()
                    if itens.count >= 4 do
                    (
                        for fe in itens[4] do
                            append G_EditFerragensLista #(fe[1], fe[2], fe[3], fe[4], fe[5], fe[6])
                    )
                    refreshEditFerrGrid()

                    -- Outros
                    local outros = itens[3]
                    try ( txtEditCola.Text  = outros[2] as string ) catch()
                    try ( txtEditMO.Text    = outros[3] as string ) catch()
                    try ( txtEditFrete.Text = outros[4] as string ) catch()
                )
            )
        )

        -- ── Setup grid cotacoes (lista esquerda) ──
        fn setupGridCotacoes =
        (
            gridCotacoes.AllowUserToAddRows    = false
            gridCotacoes.AllowUserToDeleteRows = false
            gridCotacoes.RowHeadersVisible     = false
            gridCotacoes.MultiSelect           = false
            gridCotacoes.ReadOnly              = true
            gridCotacoes.SelectionMode = (dotNetClass "System.Windows.Forms.DataGridViewSelectionMode").FullRowSelect
            gridCotacoes.Columns.Clear()
            gridCotacoes.Columns.Add (makeDGVCol "id"    "#"       34)
            gridCotacoes.Columns.Add (makeDGVCol "data"  "Data"    90)
            gridCotacoes.Columns.Add (makeDGVCol "cli"   "Cliente" 118)
            gridCotacoes.Columns.Add (makeDGVCol "proj"  "Projeto" 88)
            gridCotacoes.Columns.Add (makeDGVCol "total" "Total"   76)
            gridCotacoes.Columns.Add (makeDGVCol "desc"  "Desc%"   38)
            styleGrid gridCotacoes
        )

        local suppressCotSel = false  -- evita onSelChanged disparar durante populacao

        fn populateGridCotacoes =
        (
            suppressCotSel = true
            gridCotacoes.Rows.Clear()
            local cnt = 0
            for it in G_CotacoesLista do if it.count >= 6 do
            (
                local ri = gridCotacoes.Rows.Add()
                local rw = gridCotacoes.Rows.Item[ri]
                rw.Cells.Item[0].Value = it[1]
                rw.Cells.Item[1].Value = it[2]
                rw.Cells.Item[2].Value = it[3]
                rw.Cells.Item[3].Value = it[4]
                rw.Cells.Item[4].Value = fmtMoney it[5]
                rw.Cells.Item[5].Value = if it[6] > 0 then ((it[6] as string) + "%") else "-"
                cnt += 1
            )
            lbResultado.Text = (cnt as string) + " cotacao(oes) encontrada(s)"
            suppressCotSel = false
        )

        fn doSearch =
        (
            suppressCotSel = true
            try ( lbResultado.Text = "Pesquisando..." ) catch()
            try ( lbSpinCot.Text = "|"; lbSpinCot.Visible = true ) catch()
            ::G_ActiveSpinner = lbSpinCot
            showLoad()
            local di = try (if txtDataIni.Checked then txtDataIni.Value.ToString "yyyy-MM-dd" else "") catch ""
            local df = try (if txtDataFim.Checked then txtDataFim.Value.ToString "yyyy-MM-dd" else "") catch ""
            G_CotacoesLista = ::apiSearchCotacoes ::G_CotFiltroClienteId di df
            ::G_ActiveSpinner = undefined
            hideLoad()
            try ( lbSpinCot.Visible = false ) catch()
            suppressCotSel = false
            populateGridCotacoes()
            clearDetail()
        )

        fn aplicarFiltroCliente =
        (
            try (
                lbClienteFiltro.Text = if ::G_CotFiltroClienteId > 0 \
                    then ::G_CotFiltroClienteNome \
                    else "Todos os clientes"
            ) catch()
            doSearch()
        )

        fn onFocusIn  sender args = ( enableAccelerators = false )
        fn onFocusOut sender args = ( enableAccelerators = true  )

        fn onSelChanged sender args =
        (
            if suppressCotSel do return undefined
            local idx = 0
            try ( if gridCotacoes.SelectedRows.Count > 0 do idx = gridCotacoes.SelectedRows.Item[0].Index + 1 ) catch()
            if idx < 1 or idx > G_CotacoesLista.count do return undefined
            local cotSum = G_CotacoesLista[idx]
            G_CotId = cotSum[1]
            try ( lbSalvoStatus.Text = "Carregando..." ) catch()
            showLoad()
            local cot = ::apiGetCotacao G_CotId
            local cli = #()
            local cliId = try (cot[1] as integer) catch 0
            if cot != undefined and cliId > 0 do cli = ::apiGetCliente cliId
            hideLoad()
            if cot != undefined then
            (
                G_CotDados = #(cot, cli)
                populateResumo cot cli
                -- Uma unica chamada API compartilhada entre as duas abas de pecas
                local _itensCache = ::apiGetCotacaoItems G_CotId
                populatePecas       itensCache:_itensCache
                populatePecasEdit   itensCache:_itensCache
                populateEditar cot
            )
            else
            (
                clearDetail()
                try ( lbSalvoStatus.Text = "Erro ao carregar cotacao." ) catch()
            )
        )

        fn salvarEdicao =
        (
            if G_CotId <= 0 do ( lbSalvoStatus.Text = "Selecione uma cotacao primeiro."; return undefined )
            local desc = 0.0
            try ( desc = txtEditDesc.Text as float ) catch ( lbSalvoStatus.Text = "Desconto invalido."; return undefined )
            if desc < 0 or desc > 100 do ( lbSalvoStatus.Text = "Desconto: valor entre 0 e 100."; return undefined )
            try ( lbSalvoStatus.Text = "Salvando..." ) catch()
            showLoad()

            local proj    = try ( txtEditProj.Text    ) catch ""
            local entrega = try ( txtEditEntrega.Text ) catch ""
            local obs     = try ( txtEditObs.Text     ) catch ""
            local cola    = try ( txtEditCola.Text  as float ) catch 0.0
            local maoObra = try ( txtEditMO.Text    as float ) catch 0.0
            local frete   = try ( txtEditFrete.Text as float ) catch 0.0

            -- Coleta fitas do grid de edicao
            -- BUG2 fix: EndEdit() commita celula ativa antes de ler Value.
            -- Sem isso, clicar em Salvar enquanto uma celula esta em edicao
            -- faz Value retornar o valor ANTIGO e a alteracao se perde.
            local fitasEdit = #()
            local ccEfFitas = 0.0
            if gridEditFitas != undefined do
            (
                try ( gridEditFitas.EndEdit() ) catch()
                for r = 0 to gridEditFitas.Rows.Count - 1 do
                (
                    local prod   = try (gridEditFitas.Rows.Item[r].Cells.Item[0].Value as string) catch ""
                    -- Converte string para float; aceita virgula como separador decimal
                    local sM  = try (gridEditFitas.Rows.Item[r].Cells.Item[1].Value as string) catch "0"
                    local sV  = try (gridEditFitas.Rows.Item[r].Cells.Item[2].Value as string) catch "0"
                    local metros = try ((substituteString sM "," ".") as float) catch 0.0
                    local valM   = try ((substituteString sV "," ".") as float) catch 0.0
                    local sub    = metros * valM
                    append fitasEdit #(prod, metros, valM, sub)
                    ccEfFitas += sub
                )
            )

            -- Ferragens (atualiza qtd do grid)
            if gridEditFerr != undefined do
            (
                for r = 0 to gridEditFerr.Rows.Count - 1 do
                (
                    if (r + 1) <= G_EditFerragensLista.count do
                    (
                        local qtd = try (gridEditFerr.Rows.Item[r].Cells.Item[1].Value as integer) catch 1
                        if qtd < 1 do qtd = 1
                        local fe = G_EditFerragensLista[r + 1]
                        local sub = fe[3] * qtd
                        G_EditFerragensLista[r + 1] = #(fe[1], fe[2], fe[3], fe[4], qtd, sub)
                    )
                )
            )
            -- Converte para array de chamada; garante que todos os itens tenham subtotal (fe[6])
            local ferragParam = #()
            for fe in G_EditFerragensLista do
            (
                local qtd = if fe.count >= 5 then (try (fe[5] as integer) catch 1) else 1
                if qtd < 1 do qtd = 1
                local sub = if fe.count >= 6 then (try (fe[6] as float) catch (fe[3] * qtd)) \
                            else (fe[3] * qtd)
                append ferragParam #(fe[1], fe[2], fe[3], fe[4], qtd, sub)
            )
            local totalFerrEdit = 0.0
            for fe in ferragParam do totalFerrEdit += fe[6]

            -- Coleta chapas (precos e qtds atuais da cotacao carregada)
            local chapasEdit = #()
            local ccEfChapas = 0.0
            if G_CotDados != undefined do
            (
                local cot = G_CotDados[1]
                -- Busca chapas via items API
                local itens = ::apiGetCotacaoItems G_CotId
                if itens != undefined do
                    for ch in itens[1] do
                    (
                        append chapasEdit #(ch[1], ch[2], ch[3], ch[4], ch[5])
                        ccEfChapas += ch[3] * ch[4]  -- qtd * valorUnit (sem desp)
                    )
            )

            local outrosArr = #(totalFerrEdit, cola, maoObra, frete)
            local ccEfOutros = totalFerrEdit + frete  -- efetivo = ferragens + frete (exclui cola/maoObra)
            local ccEfGeral  = (ccEfChapas + ccEfFitas + ccEfOutros) * (1.0 - desc / 100.0)

            -- ── Recalculo CMC+Markup v9 ─────────────────────────────────────
            -- Chapas nao mudam na edicao; apenas fitas/ferragens/cola/frete/MO.
            local cotCarregada = if G_CotDados != undefined then G_CotDados[1] else undefined

            -- custo_produto_chapas: parte chapas do CMC (nao muda na edicao)
            -- cot[17] = custo_produto_chapas (novo array alinhado, requere apiGetCotacao v2)
            local cpChapas = if cotCarregada != undefined and cotCarregada.count >= 17 \
                             then (try (cotCarregada[17] as float) catch 0.0) else 0.0

            -- Fallback robusto: se cpChapas for 0, recalcula como CMC_armazenado - fitas_armazenadas
            -- Garante correto funcionamento mesmo em cotacoes criadas com versao anterior
            if cpChapas == 0.0 do
            (
                local oldCmc     = if cotCarregada != undefined and cotCarregada.count >= 23 \
                                   then (try (cotCarregada[23] as float) catch 0.0) else 0.0
                local oldCpFitas = if cotCarregada != undefined and cotCarregada.count >= 18 \
                                   then (try (cotCarregada[18] as float) catch 0.0) else 0.0
                -- Segundo fallback: custo_produto_geral (legacy CMC total) se custo_material_consumido for 0
                if oldCmc == 0.0 do
                    oldCmc = if cotCarregada != undefined and cotCarregada.count >= 16 \
                             then (try (cotCarregada[16] as float) catch 0.0) else 0.0
                cpChapas = oldCmc - oldCpFitas
                if cpChapas < 0.0 do cpChapas = 0.0
            )

            local margemPct = if cotCarregada != undefined and cotCarregada.count >= 25 \
                              then (try (cotCarregada[25] as float) catch 0.0) else 0.0
            local impostoPctEd  = if cotCarregada != undefined and cotCarregada.count >= 27 \
                                  then (try (cotCarregada[27] as float) catch 0.0) else 0.0
            local comissaoPctEd = if cotCarregada != undefined and cotCarregada.count >= 28 \
                                  then (try (cotCarregada[28] as float) catch 0.0) else 0.0

            -- CMC = chapas consumidas (imutavel) + fitas novas
            local newCmc = cpChapas + ccEfFitas
            -- COB = CMC + ferragens + cola + frete + MO
            local newCob = newCmc + totalFerrEdit + cola + frete + maoObra
            -- PV  = COB / (1 - (margem+imposto+comissao)/100) x (1 - desconto%)  [markup divisor v10]
            local pctTotalEd = margemPct + impostoPctEd + comissaoPctEd
            if pctTotalEd > 95.0 do pctTotalEd = 95.0
            local newPV  = (newCob / (1.0 - pctTotalEd / 100.0)) * (1.0 - desc / 100.0)
            -- CA  = chapas + fitas + ferragens + cola + frete  (sem MO)
            local newCA  = cpChapas + ccEfFitas + totalFerrEdit + cola + frete
            -- custo_produto_outros = ferragens + frete (sem cola/MO — definicao v9)
            local newCpOutros = totalFerrEdit + frete
            -- custo_produto_geral  = CMC (chapas+fitas) + outros_produto
            local newCpGeral  = newCmc + newCpOutros

            local res = ::apiAtualizarCotacaoFull G_CotId proj entrega obs desc \
                chapasEdit fitasEdit ferragParam outrosArr \
                ccEfChapas ccEfFitas ccEfOutros ccEfGeral \
                maoObra:maoObra cmcVal:newCmc cobVal:newCob margemPct:margemPct \
                precoVenda:newPV caTotal:newCA cpFitas:ccEfFitas \
                cpOutros:newCpOutros cpGeral:newCpGeral \
                impostoPct:impostoPctEd comissaoPct:comissaoPctEd
            hideLoad()
            if res[1] then
            (
                for it in G_CotacoesLista do if it[1] == G_CotId do it[6] = desc
                populateGridCotacoes()
                local cot = ::apiGetCotacao G_CotId
                local cli = if G_CotDados != undefined then G_CotDados[2] else #()
                if cot != undefined do ( G_CotDados = #(cot, cli); populateResumo cot cli )
                lbSalvoStatus.Text = res[2]
            )
            else lbSalvoStatus.Text = "Erro: " + res[2]
        )

        fn buildUi =
        (
            -- pnlLeft e tabCtrl sao dotNetControl declarados no rollout —
            -- o MaxScript ja aplicou DPI scaling corretamente nas suas posicoes/tamanhos.
            -- Usamos ClientSize para ler os pixels reais disponiveis.
            pnlLeft.Controls.Clear()
            tabCtrl.TabPages.Clear()

            -- ── COLUNA ESQUERDA ──
            -- Leitura do tamanho real de pnlLeft em pixels logicos .NET
            local LW = try (pnlLeft.ClientSize.Width)  catch 380
            local LH = try (pnlLeft.ClientSize.Height) catch 762

            local grpFiltros = addGrp pnlLeft "Filtros" 0 0 LW 148
            addLbl grpFiltros "Cliente:" 8 22 54 16
            lbClienteFiltro = addLbl grpFiltros "Todos os clientes" 66 22 (LW - 82) 16
            btnSelectCli = addBtn grpFiltros "Selecionar..." 8  44 180 26
            btnLimparCli = addBtn grpFiltros "Limpar"        194 44 (LW - 202) 26
            addLbl grpFiltros "De:"  8  84 26 16
            txtDataIni   = addDate grpFiltros 36 80 130 26
            addLbl grpFiltros "Ate:" 174 84 28 16
            txtDataFim   = addDate grpFiltros 204 80 (LW - 212) 26
            btnPesquisar = addBtn grpFiltros "Pesquisar" 8 112 (LW - 16) 28

            lbResultado = addLbl pnlLeft "0 cotacoes" 0 156 LW 16

            gridCotacoes = dotNetObject "System.Windows.Forms.DataGridView"
            gridCotacoes.Location = dnPt 0 174
            gridCotacoes.Size     = dnSz LW (LH - 200)
            try ( gridCotacoes.Anchor = 7 ) catch()  -- Top|Bottom|Left
            pnlLeft.Controls.Add gridCotacoes
            setupGridCotacoes()

            lbSpinCot = addLbl pnlLeft "|" 0 (LH - 18) 120 14
            lbSpinCot.Visible = false

            -- ── COLUNA DIREITA: tabCtrl ja posicionado pelo rollout ──
            -- Leitura do tamanho real em pixels logicos .NET
            local TW = try (tabCtrl.ClientSize.Width)  catch 696
            local TH = try (tabCtrl.ClientSize.Height) catch 762

            -- ──── TAB 1: Resumo ────
            local tabResumo = dotNetObject "System.Windows.Forms.TabPage"
            tabResumo.Text = "  Resumo  "
            tabCtrl.TabPages.Add tabResumo

            -- Conteudo da aba Resumo
            local IW = TW - 20  -- inner width

            local grpCli = addGrp tabResumo "Cliente" 4 4 IW 120
            addLbl grpCli "Nome:"      8 22 60 16; lbCliNome  = addLbl grpCli "—" 72  22 (IW-80) 16
            addLbl grpCli "Documento:" 8 44 70 16; lbCliDoc   = addLbl grpCli "—" 82  44 200 16
            addLbl grpCli "Telefone:"  300 44 60 16; lbCliTel = addLbl grpCli "—" 364 44 (IW-372) 16
            addLbl grpCli "E-mail:"    8 66 52 16; lbCliEmail = addLbl grpCli "—" 62  66 (IW-70) 16
            addLbl grpCli "Cidade/UF:" 8 88 66 16; lbCliCid   = addLbl grpCli "—" 78  88 (IW-86) 16

            local grpProj = addGrp tabResumo "Projeto" 4 132 IW 110
            addLbl grpProj "Nome:"    8 22 50 16; lbProjNome    = addLbl grpProj "—" 62 22 (IW-70) 16
            addLbl grpProj "Entrega:" 8 44 56 16; lbProjEntrega = addLbl grpProj "—" 68 44 280 16
            addLbl grpProj "Obs:"     8 66 32 16; lbProjObs     = addLbl grpProj "" 44 66 (IW-52) 36

            local grpFin = addGrp tabResumo "Financeiro" 4 250 IW 390
            lbFinCh      = addLbl grpFin "" 8 22 (IW-16) 18
            lbFinFt      = addLbl grpFin "" 8 42 (IW-16) 18
            lbFinOu      = addLbl grpFin "" 8 62 (IW-16) 18
            addLbl grpFin "─────────────────────────────────" 8 80 (IW-16) 16
            lbFinSub     = addLbl grpFin "" 8 98  (IW-16) 18
            lbFinDesc    = addLbl grpFin "" 8 118 (IW-16) 18
            lbFinTot     = addLbl grpFin "Selecione uma cotacao" 8 142 (IW-16) 26
            -- Seção interna CMC+Markup (oculta em cotacoes antigas)
            addLbl grpFin "─────────────────────────────────" 8 174 (IW-16) 16
            lbFinMO      = addLbl grpFin "" 8 192 (IW-16) 18   -- MO
            lbFinCMC     = addLbl grpFin "" 8 212 (IW-16) 18   -- CMC
            lbFinCOB     = addLbl grpFin "" 8 232 (IW-16) 18   -- COB
            lbFinMargem  = addLbl grpFin "" 8 252 (IW-16) 18   -- Margem%
            lbFinPV      = addLbl grpFin "" 8 272 (IW-16) 22   -- PV Final
            -- CA (referencia interna)
            addLbl grpFin "─────────────────────────────────" 8 298 (IW-16) 16
            lbFinEfetivo = addLbl grpFin "" 8 316 (IW-16) 18   -- CA Total
            lbFinProduto = addLbl grpFin "" 8 336 (IW-16) 18   -- (reserva)

            -- ──── TAB 2: Pecas ────
            local tabPecas = dotNetObject "System.Windows.Forms.TabPage"
            tabPecas.Text = "  Pecas Utilizadas  "
            tabCtrl.TabPages.Add tabPecas

            gridPecas = dotNetObject "System.Windows.Forms.DataGridView"
            gridPecas.Location = dnPt 4 4
            gridPecas.Size     = dnSz (TW - 12) (TH - 36)
            gridPecas.AllowUserToAddRows    = false
            gridPecas.AllowUserToDeleteRows = false
            gridPecas.RowHeadersVisible     = false
            gridPecas.MultiSelect           = false
            gridPecas.ReadOnly              = true
            gridPecas.SelectionMode = (dotNetClass "System.Windows.Forms.DataGridViewSelectionMode").FullRowSelect
            gridPecas.Columns.Add (makeDGVCol "prod"    "Produto / Descricao"  260)
            gridPecas.Columns.Add (makeDGVCol "esp"     "Esp/Detalhe"           90)
            gridPecas.Columns.Add (makeDGVCol "qtd"     "Qtd"                   54)
            gridPecas.Columns.Add (makeDGVCol "unit"    "Unit."                 90)
            gridPecas.Columns.Add (makeDGVCol "subtot"  "Subtotal"              90)
            tabPecas.Controls.Add gridPecas
            styleGrid gridPecas

            -- ──── TAB 3: Editar ────
            local tabEditar = dotNetObject "System.Windows.Forms.TabPage"
            tabEditar.Text = "  Editar Orcamento  "
            tabCtrl.TabPages.Add tabEditar

            -- Painel scrollavel para caber todos os campos
            local pnlEd = dotNetObject "System.Windows.Forms.Panel"
            pnlEd.Location = dnPt 0 0
            pnlEd.Size     = dnSz (TW - 6) (TH - 32)
            pnlEd.AutoScroll = true
            tabEditar.Controls.Add pnlEd

            local EW = TW - 30  -- largura efetiva dos controles

            -- ─── Projeto ───
            local grpProjEd = addGrp pnlEd "Projeto" 4 4 EW 192
            addLbl grpProjEd "Nome do Projeto:"      8 26 130 16
            txtEditProj    = addTxt grpProjEd 142 24 (EW - 150) 26
            addLbl grpProjEd "Previsao de Entrega:"  8 60 138 16
            txtEditEntrega = addTxt grpProjEd 148 58 180 26
            addLbl grpProjEd "Desconto Global (%):"  8 94 140 16
            txtEditDesc    = addTxt grpProjEd 148 92 80 26
            addLbl grpProjEd "Observacoes:"          8 128 100 16
            txtEditObs     = addTxt grpProjEd 8 148 (EW - 16) 36 multiline:true

            -- ─── Fitas de Borda ───
            local grpFitasEd = addGrp pnlEd "Fitas de Borda" 4 200 EW 180
            gridEditFitas = dotNetObject "System.Windows.Forms.DataGridView"
            gridEditFitas.Location = dnPt 8 22
            gridEditFitas.Size     = dnSz (EW - 16) 100
            gridEditFitas.AllowUserToAddRows    = false
            gridEditFitas.AllowUserToDeleteRows = false
            gridEditFitas.RowHeadersVisible     = false
            gridEditFitas.MultiSelect           = false
            gridEditFitas.SelectionMode = (dotNetClass "System.Windows.Forms.DataGridViewSelectionMode").FullRowSelect
            local cEF1 = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"
            cEF1.Name = "prod"; cEF1.HeaderText = "Produto"; cEF1.Width = 260; cEF1.ReadOnly = true
            local cEF2 = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"
            cEF2.Name = "metros"; cEF2.HeaderText = "Metros"; cEF2.Width = 80
            local cEF3 = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"
            cEF3.Name = "valm"; cEF3.HeaderText = "R$/m"; cEF3.Width = 80
            local cEF4 = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"
            cEF4.Name = "sub"; cEF4.HeaderText = "Subtotal"; cEF4.Width = 90; cEF4.ReadOnly = true
            gridEditFitas.Columns.Add cEF1; gridEditFitas.Columns.Add cEF2
            gridEditFitas.Columns.Add cEF3; gridEditFitas.Columns.Add cEF4
            grpFitasEd.Controls.Add gridEditFitas
            styleGrid gridEditFitas
            btnEditFitaBuscar = addBtn grpFitasEd "Buscar na API"    8  128 130 28
            btnEditFitaAdd    = addBtn grpFitasEd "+ Fita"          144  128  80 28
            btnEditFitaRemove = addBtn grpFitasEd "- Remover"       230  128  80 28

            -- ─── Ferragens ───
            local grpFerrEd = addGrp pnlEd "Ferragens" 4 386 EW 180
            gridEditFerr = dotNetObject "System.Windows.Forms.DataGridView"
            gridEditFerr.Location = dnPt 8 22
            gridEditFerr.Size     = dnSz (EW - 16) 100
            gridEditFerr.AllowUserToAddRows    = false
            gridEditFerr.AllowUserToDeleteRows = false
            gridEditFerr.RowHeadersVisible     = false
            gridEditFerr.MultiSelect           = false
            gridEditFerr.SelectionMode = (dotNetClass "System.Windows.Forms.DataGridViewSelectionMode").FullRowSelect
            local cFR1 = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"
            cFR1.Name = "nome"; cFR1.HeaderText = "Nome"; cFR1.Width = 270; cFR1.ReadOnly = true
            local cFR2 = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"
            cFR2.Name = "qtd"; cFR2.HeaderText = "Qtd"; cFR2.Width = 50
            local cFR3 = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"
            cFR3.Name = "vunit"; cFR3.HeaderText = "Valor Un."; cFR3.Width = 80; cFR3.ReadOnly = true
            local cFR4 = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"
            cFR4.Name = "sub"; cFR4.HeaderText = "Subtotal"; cFR4.Width = 90; cFR4.ReadOnly = true
            gridEditFerr.Columns.Add cFR1; gridEditFerr.Columns.Add cFR2
            gridEditFerr.Columns.Add cFR3; gridEditFerr.Columns.Add cFR4
            grpFerrEd.Controls.Add gridEditFerr
            styleGrid gridEditFerr
            btnEditFerrBuscar = addBtn grpFerrEd "Buscar Ferragem"    8 128 140 28
            btnEditFerrRemove = addBtn grpFerrEd "- Remover"         154 128  90 28

            -- ─── Outros Custos ───
            local grpOutrosEd = addGrp pnlEd "Outros Custos" 4 572 EW 110
            addLbl grpOutrosEd "Cola (R$):"       8 26  90 16
            txtEditCola = addTxt grpOutrosEd 100 24 90 26
            addLbl grpOutrosEd "Mao de Obra (R$):" 210 26 110 16
            txtEditMO   = addTxt grpOutrosEd 322 24 90 26
            addLbl grpOutrosEd "Frete (R$):"      430 26  70 16
            txtEditFrete = addTxt grpOutrosEd 502 24 90 26

            -- ─── Salvar ───
            btnSalvarEdit = addBtn pnlEd "Salvar Alteracoes" 4 690 200 32
            lbSalvoStatus = addLbl pnlEd "" 212 698 (EW - 210) 20

            -- ──── TAB 4: Editar Pecas ────
            local tabEditPecas = dotNetObject "System.Windows.Forms.TabPage"
            tabEditPecas.Text = "  Editar Pecas  "
            tabCtrl.TabPages.Add tabEditPecas

            -- Margens consistentes (respiro): 12px lateral, rodape de 84px
            local MGN = 12
            local FOOT = 84
            local GH  = TH - FOOT - MGN            -- altura util do grid
            local GWp = TW - (MGN * 2) - 4         -- largura util do grid

            gridEditPecas = dotNetObject "System.Windows.Forms.DataGridView"
            gridEditPecas.Location = dnPt MGN MGN
            gridEditPecas.Size     = dnSz GWp GH
            gridEditPecas.AllowUserToAddRows    = false
            gridEditPecas.AllowUserToDeleteRows = false
            gridEditPecas.MultiSelect           = false
            gridEditPecas.EditMode = (dotNetClass "System.Windows.Forms.DataGridViewEditMode").EditOnKeystrokeOrF2
            gridEditPecas.SelectionMode = (dotNetClass "System.Windows.Forms.DataGridViewSelectionMode").CellSelect

            -- Helper para criar coluna de texto com peso de preenchimento
            fn mkTxtCol nm hd weight ro:false =
            (
                local c = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"
                c.Name = nm; c.HeaderText = hd; c.FillWeight = weight; c.ReadOnly = ro; c
            )
            fn mkChkCol nm hd weight =
            (
                local c = dotNetObject "System.Windows.Forms.DataGridViewCheckBoxColumn"
                c.Name = nm; c.HeaderText = hd; c.FillWeight = weight
                c.DefaultCellStyle.Alignment = (dotNetClass "System.Windows.Forms.DataGridViewContentAlignment").MiddleCenter
                c
            )

            -- Colunas (FillWeight ~ proporcao da largura; somam ~700, normalizadas pelo Fill)
            gridEditPecas.Columns.Add (mkTxtCol "nome" "Nome"        150)
            gridEditPecas.Columns.Add (mkTxtCol "comp" "Comp (mm)"    78)
            gridEditPecas.Columns.Add (mkTxtCol "larg" "Larg (mm)"    78)
            gridEditPecas.Columns.Add (mkTxtCol "esp"  "Esp (mm)"     62)
            gridEditPecas.Columns.Add (mkTxtCol "qtd"  "Qtd"          46)
            gridEditPecas.Columns.Add (mkChkCol "fc1"  "C1"           34)
            gridEditPecas.Columns.Add (mkChkCol "fc2"  "C2"           34)
            gridEditPecas.Columns.Add (mkChkCol "fl1"  "L1"           34)
            gridEditPecas.Columns.Add (mkChkCol "fl2"  "L2"           34)
            gridEditPecas.Columns.Add (mkTxtCol "aunit" "m² Unit"     70 ro:true)
            gridEditPecas.Columns.Add (mkTxtCol "atot"  "m² Total"    70 ro:true)

            tabEditPecas.Controls.Add gridEditPecas
            styleGrid gridEditPecas fillCols:true

            -- Destaca colunas calculadas (read-only) com fundo suave
            try (
                local clrRO = (dotNetClass "System.Drawing.Color").FromArgb 242 245 248
                gridEditPecas.Columns.Item[9].DefaultCellStyle.BackColor  = clrRO
                gridEditPecas.Columns.Item[10].DefaultCellStyle.BackColor = clrRO
                gridEditPecas.Columns.Item[10].DefaultCellStyle.Font = dotNetObject "System.Drawing.Font" "Segoe UI" 9.0 \
                    ((dotNetClass "System.Drawing.FontStyle").Bold)
            ) catch()

            -- ─── Rodape com respiro ───
            local footY = TH - FOOT + 6
            -- Faixa de total (destaque)
            lbPecasTotalM2 = addLbl tabEditPecas "Total M² consumido: 0.0000 m²" MGN footY 360 26
            try (
                lbPecasTotalM2.Font = dotNetObject "System.Drawing.Font" "Segoe UI" 11.0 \
                    ((dotNetClass "System.Drawing.FontStyle").Bold)
                lbPecasTotalM2.ForeColor = (dotNetClass "System.Drawing.Color").FromArgb 26 99 60
            ) catch()
            -- Botoes alinhados a direita com gap
            local btnW = 150
            local gap  = 10
            local bx2  = TW - MGN - btnW           -- Salvar (primario) na borda direita
            local bx1  = bx2 - gap - btnW          -- Restaurar a esquerda dele
            btnRestaurarPecas = addBtn tabEditPecas "Restaurar Original" bx1 footY btnW 30
            btnSalvarPecas    = addBtn tabEditPecas "Salvar Alteracoes"  bx2 footY btnW 30
            try ( ::pintarBotaoProximo btnSalvarPecas ) catch()
            -- Status abaixo, alinhado ao total
            lbPecasSalvStatus = addLbl tabEditPecas "" MGN (footY + 34) (TW - MGN*2) 18
            try ( lbPecasSalvStatus.ForeColor = (dotNetClass "System.Drawing.Color").FromArgb 90 96 104 ) catch()

            -- pnlLoad declarado no rollout; mantido invisivel (nao usado como overlay)
            try ( pnlLoad.Visible = false ) catch()

            -- ── Event handlers ──
            dotNet.addEventHandler gridCotacoes "SelectionChanged" onSelChanged
            dotNet.addEventHandler gridCotacoes "CellDoubleClick"  onSelChanged
            dotNet.addEventHandler btnPesquisar "Click" (fn s a = doSearch())
            dotNet.addEventHandler btnSelectCli "Click" (fn s a = ::abrirFiltroClienteCotacoes())
            dotNet.addEventHandler btnLimparCli "Click" (fn s a = (
                ::G_CotFiltroClienteId   = 0
                ::G_CotFiltroClienteNome = ""
                try ( lbClienteFiltro.Text = "Todos os clientes" ) catch()
                doSearch()
            ))
            dotNet.addEventHandler btnSalvarEdit "Click" (fn s a = salvarEdicao())

            -- Aba Editar Pecas — recalcular area ao editar celula
            dotNet.addEventHandler gridEditPecas "CellEndEdit" (fn s a =
            (
                try (
                    recalcPecasRow a.RowIndex
                    recalcPecasTotal()
                ) catch()
            ))
            -- FIX: CheckBox no DataGridView só comita o valor ao perder foco.
            -- CurrentCellDirtyStateChanged + CommitEdit forca commit imediato
            -- no primeiro clique, evitando que o ultimo checkbox editado nao
            -- seja capturado por serializePecasGrid ao clicar em Salvar.
            dotNet.addEventHandler gridEditPecas "CurrentCellDirtyStateChanged" (fn s a =
            (
                try (
                    if gridEditPecas.IsCurrentCellDirty do
                        gridEditPecas.CommitEdit \
                            ((dotNetClass "System.Windows.Forms.DataGridViewDataErrorContexts").Commit)
                ) catch()
            ))
            -- CellValueChanged dispara para checkboxes (que nao geram CellEndEdit)
            dotNet.addEventHandler gridEditPecas "CellValueChanged" (fn s a =
            (
                try (
                    local colIdx = a.ColumnIndex
                    if colIdx >= 5 and colIdx <= 8 do
                    (
                        recalcPecasRow a.RowIndex
                        recalcPecasTotal()
                    )
                ) catch()
            ))
            dotNet.addEventHandler btnSalvarPecas "Click" (fn s a =
            (
                if G_CotId <= 0 do return undefined
                -- Forca commit da celula ativa antes de serializar
                try ( gridEditPecas.EndEdit() ) catch()
                try ( lbPecasSalvStatus.Text = "Salvando..." ) catch()
                windows.processPostedMessages()
                showLoad()
                local jsonStr = serializePecasGrid()
                -- Grava payload minimo: apenas cotacao_id + pecas_json
                -- handle_update_cotacao_full preserva todos os outros campos (R1)
                local tmpFile = (::dirSep ::sysInfo.tempDir) + "cnc_cotacao_update.txt"
                local payload = "{\"cotacao_id\":" + (G_CotId as string) + ",\"pecas_json\":" + jsonStr + "}"
                local fOk = false
                try (
                    local fw = createFile tmpFile
                    if fw != undefined do (
                        format "%" payload to:fw
                        close fw
                        fOk = true
                    )
                ) catch()
                if not fOk do (
                    hideLoad()
                    try ( lbPecasSalvStatus.Text = "Erro ao gravar arquivo." ) catch()
                    return undefined
                )
                if not (::apiWriteCmd "update_cotacao_full") do (
                    hideLoad()
                    try ( lbPecasSalvStatus.Text = "Erro de comunicacao." ) catch()
                    return undefined
                )
                local res = ::apiExecute()
                hideLoad()
                if res.count >= 1 and res[1] == "OK" then
                (
                    try ( lbPecasSalvStatus.Text = "Salvando... recarregando." ) catch()
                    windows.processPostedMessages()
                    populatePecasEdit()
                    try ( lbPecasSalvStatus.Text = "Salvo e recarregado com sucesso." ) catch()
                )
                else
                    try ( lbPecasSalvStatus.Text = "Erro ao salvar: " + (if res.count >= 2 then res[2] else "?") ) catch()
            ))
            dotNet.addEventHandler btnRestaurarPecas "Click" (fn s a =
            (
                populatePecasEdit()
                try ( lbPecasSalvStatus.Text = "Dados restaurados do banco." ) catch()
            ))

            -- Botoes da aba Editar — Fitas
            dotNet.addEventHandler btnEditFitaBuscar "Click" (fn s a =
            (
                if not ::G_ApiOnline do return undefined
                local rowIdx = 1
                try ( if gridEditFitas.SelectedRows.Count > 0 do rowIdx = gridEditFitas.SelectedRows.Item[0].Index + 1 ) catch()
                ::G_BuscaFitaTargetRow = rowIdx
                -- Sincroniza G_FitasMultiLinhas com o grid de edicao antes de abrir modal
                ::G_FitasMultiLinhas = #()
                for r = 0 to gridEditFitas.Rows.Count - 1 do
                (
                    local prod   = try (gridEditFitas.Rows.Item[r].Cells.Item[0].Value as string) catch ""
                    local metros = try (gridEditFitas.Rows.Item[r].Cells.Item[1].Value as float) catch 0.0
                    local valM   = try (gridEditFitas.Rows.Item[r].Cells.Item[2].Value as float) catch 0.0
                    append ::G_FitasMultiLinhas #(prod, metros, valM, 50.0, "")
                )
                ::abrirBuscaFitaAPI rowIdx "Geral"
                -- Apos fechar modal, atualiza grid de edicao
                local fitasEdit = #()
                for ft in ::G_FitasMultiLinhas do
                    append fitasEdit #(ft[1], ft[2], ft[3], ft[2]*ft[3])
                refreshEditFitasGrid fitasEdit
            ))
            dotNet.addEventHandler btnEditFitaAdd "Click" (fn s a =
            (
                local ri = gridEditFitas.Rows.Add()
                local rw = gridEditFitas.Rows.Item[ri]
                rw.Cells.Item[0].Value = "(Selecionar)"
                rw.Cells.Item[1].Value = "0"
                rw.Cells.Item[2].Value = "0"
                rw.Cells.Item[3].Value = fmtMoney 0.0
            ))
            dotNet.addEventHandler btnEditFitaRemove "Click" (fn s a =
            (
                if gridEditFitas.SelectedRows.Count > 0 and gridEditFitas.Rows.Count > 1 do
                (
                    local idx = gridEditFitas.SelectedRows.Item[0].Index
                    gridEditFitas.Rows.RemoveAt idx
                )
            ))

            -- Botoes da aba Editar — Ferragens
            dotNet.addEventHandler btnEditFerrBuscar "Click" (fn s a =
            (
                if not ::G_ApiOnline do return undefined
                -- Sincroniza G_FerragensLista com lista de edicao antes de abrir modal
                ::G_FerragensLista = G_EditFerragensLista
                -- O modal e MODELESS: registra callback para recarregar o grid ao fechar
                ::G_FerragemDialogOnClose = (fn ferrCb = (
                    try ( ::G_ActiveCotacoesRl.recarregarFerrEdicao() ) catch()
                ))
                ::abrirBuscaFerragemAPI()
            ))
            dotNet.addEventHandler btnEditFerrRemove "Click" (fn s a =
            (
                if gridEditFerr.SelectedRows.Count > 0 do
                (
                    local idx = gridEditFerr.SelectedRows.Item[0].Index + 1
                    if idx >= 1 and idx <= G_EditFerragensLista.count do
                    (
                        local novaLista = #()
                        for i = 1 to G_EditFerragensLista.count do
                            if i != idx do append novaLista G_EditFerragensLista[i]
                        G_EditFerragensLista = novaLista
                        refreshEditFerrGrid()
                    )
                )
            ))

            -- Suspende aceleradores do Max para campos de texto
            for tb in #(txtEditProj, txtEditEntrega, txtEditDesc, txtEditObs, txtEditCola, txtEditMO, txtEditFrete) do
            (
                dotNet.addEventHandler tb "GotFocus"  onFocusIn
                dotNet.addEventHandler tb "LostFocus" onFocusOut
            )
        )

        on rlCotacoes open do
        (
            ::G_ActiveCotacoesRl     = rlCotacoes
            ::G_CotFiltroClienteId   = 0
            ::G_CotFiltroClienteNome = ""
            btnVoltar.Text         = "← Voltar"
            btnExportPDF.Text      = "Exportar PDF (HTML)"
            btnExportProposta.Text = "📄 Proposta ao Cliente"
            btnExportProposta.BackColor = (dotNetClass "System.Drawing.Color").FromArgb 75 46 27
            btnExportProposta.ForeColor = (dotNetClass "System.Drawing.Color").White
            lbRodape.Text     = "Selecione uma cotacao para ver os detalhes."
            buildUi()
            try ( ::aplicarTemaForm lbRodape.FindForm() ) catch()
            lbResultado.Text = "Clique em Pesquisar para carregar cotacoes."
        )

        on btnVoltar Click sender args do destroyDialog rlCotacoes

        on btnExportPDF Click sender args do
        (
            if G_CotId <= 0 do
            (
                messageBox "Selecione uma cotacao primeiro." title:"Exportar"
                return undefined
            )
            lbRodape.Text = "Gerando relatorio HTML..."
            windows.processPostedMessages()
            local ok = ::apiExportCotacaoHTML G_CotId
            lbRodape.Text = if ok then "Relatorio aberto no navegador." \
                                  else "Erro ao gerar relatorio."
        )

        on btnExportProposta Click sender args do
        (
            if G_CotId <= 0 do
            (
                messageBox "Selecione uma cotacao primeiro." title:"Proposta ao Cliente"
                return undefined
            )
            lbRodape.Text = "Gerando proposta para o cliente..."
            windows.processPostedMessages()
            local ok = ::apiExportPropostaClienteHTML G_CotId
            lbRodape.Text = if ok then "Proposta aberta no navegador." \
                                  else "Erro ao gerar proposta."
        )
    )

    createDialog rlCotacoes style:#(#style_titlebar, #style_border, #style_sysmenu) bgcolor:(color 245 246 248)
)

-- ============================================================
-- FEATURE 1: VerificaÃ§Ã£o de API na inicializaÃ§Ã£o
-- ============================================================
fn verificarEIniciar =
(
    -- Detecta executavel Python para chamadas nao-bloqueantes (spinner animado)
    G_PythonExe = detectPythonExe()
    format "Python exe: %\n" G_PythonExe

    format "Verificando API Banco de Dados...\n"
    local online = apiHealthCheck()

    if online then
    (
        format "API Banco de Dados: ONLINE\n"
        abrirUIPrincipal()
    )
    else
    (
        rollout rlApiCheck "API Banco de Dados" width:430 height:180
        (
            dotNetControl lbMsg1   "System.Windows.Forms.Label" pos:[20,18]  width:390 height:18
            dotNetControl lbMsg2   "System.Windows.Forms.Label" pos:[20,45]  width:390 height:18
            dotNetControl lbMsg3   "System.Windows.Forms.Label" pos:[20,70]  width:390 height:18
            dotNetControl lbSpin   "System.Windows.Forms.Label" pos:[200,90] width:30  height:18
            dotNetControl btnStart "System.Windows.Forms.Button" pos:[36,112]  width:170 height:34
            dotNetControl btnSkip  "System.Windows.Forms.Button" pos:[224,112] width:170 height:34

            fn onStart sender args =
            (
                lbMsg2.Text  = "Iniciando API... aguarde (ate 20s)..."
                lbSpin.Text  = "|"
                lbSpin.Visible = true
                ::G_ActiveSpinner = lbSpin
                btnStart.Enabled = false
                btnSkip.Enabled  = false
                local ok = ::apiStartServer()
                ::G_ActiveSpinner = undefined
                lbSpin.Visible = false
                if ok then
                (
                    messageBox "API iniciada com sucesso!" title:"API OK"
                    destroyDialog rlApiCheck
                    ::abrirUIPrincipal()
                )
                else
                (
                    lbMsg2.Text = "Falha ao iniciar. Verifique PostgreSQL e tente novamente."
                    btnStart.Enabled = true
                    btnSkip.Enabled = true
                )
            )

            fn onSkip sender args =
            (
                destroyDialog rlApiCheck
                ::abrirUIPrincipal()
            )

            on rlApiCheck open do
            (
                try ( ::aplicarTemaForm lbMsg1.FindForm() ) catch()
                local ca = (dotNetClass "System.Drawing.ContentAlignment").MiddleCenter
                lbMsg1.Text      = "API Banco de Dados nao encontrada em gauswoods.com.br"
                lbMsg1.TextAlign = ca
                lbMsg2.Text      = "Deseja inicia-la automaticamente?"
                lbMsg2.TextAlign = ca
                lbMsg3.Text      = "(necessario PostgreSQL rodando)"
                lbMsg3.TextAlign = ca
                btnStart.Text    = "Iniciar API"
                btnSkip.Text     = "Continuar sem API"
                lbSpin.Visible   = false
            )

            on btnStart Click sender args do onStart sender args
            on btnSkip Click sender args do onSkip sender args
        )

        createDialog rlApiCheck style:#(#style_titlebar, #style_border, #style_sysmenu) bgcolor:(color 245 246 248)
    )
)

verificarEIniciar()
