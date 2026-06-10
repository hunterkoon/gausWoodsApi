clearlistener()

-- Variáveis Globais de Controle de Fase
global G_PiecesData = #()
global G_MainConfig = #()
global G_FitaTh = 1.0
global fltFitas = undefined

-- Estrutura da Peça
struct PieceObj ( node, nome, comp, larg, esp, c1, c2, l1, l2 )

-- ============================================================
-- FUNÇÕES AUXILIARES GLOBAIS
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
-- MOTOR DE ORDENAÇÃO
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
-- ALGORITMO DE EMPACOTAMENTO
-- ============================================================
fn packPieceHorizontal boards w d binW binD gap allowRot =
(
    local opts = if allowRot then #( #(w,d, false), #(d,w, true) ) else #( #(w,d, false) )
    if allowRot and abs(w - d) < 0.001 do opts = #( #(w,d, false) )

    local bestB = 0; local bestPx = 0.0; local bestPy = 0.0; local bestRot = false; local foundExact = false

    for opt in opts while not foundExact do
    (
        local tw = opt[1]; local th = opt[2]
        for i = 1 to boards.count while not foundExact do
        (
            local b = boards[i]
            for j = 1 to b[2].count while not foundExact do
            (
                local s = b[2][j]
                if abs(th - s[3]) < 0.1 and tw <= s[4] + 0.001 do
                (
                    bestB = i; bestPx = s[2]; bestPy = s[1]; bestRot = opt[3]
                    s[2] += tw + gap; s[4] -= (tw + gap); foundExact = true
                )
            )
        )
    )
    if foundExact do return #(bestB, bestPx, bestPy, bestRot)

    local foundAny = false
    for opt in opts while not foundAny do
    (
        local tw = opt[1]; local th = opt[2]
        for i = 1 to boards.count while not foundAny do
        (
            local b = boards[i]
            for j = 1 to b[2].count while not foundAny do
            (
                local s = b[2][j]
                if th <= s[3] + 0.001 and tw <= s[4] + 0.001 do
                (
                    bestB = i; bestPx = s[2]; bestPy = s[1]; bestRot = opt[3]
                    s[2] += tw + gap; s[4] -= (tw + gap); foundAny = true
                )
            )
        )
    )
    if foundAny do return #(bestB, bestPx, bestPy, bestRot)

    local sortedOpts = deepCopy opts
    if sortedOpts.count > 1 and sortedOpts[1][2] > sortedOpts[2][2] do ( local temp = sortedOpts[1]; sortedOpts[1] = sortedOpts[2]; sortedOpts[2] = temp )
    
    local createdShelf = false
    for opt in sortedOpts while not createdShelf do
    (
        local tw = opt[1]; local th = opt[2]
        for i = 1 to boards.count while not createdShelf do
        (
            local b = boards[i]
            if th <= b[1] + 0.001 and tw <= binW + 0.001 do
            (
                local newY = 0.0
                if b[2].count > 0 do ( local lastS = b[2][b[2].count]; newY = lastS[1] + lastS[3] + gap )
                append b[2] #(newY, tw + gap, th, binW - (tw + gap))
                b[1] -= (th + gap)
                bestB = i; bestPx = 0.0; bestPy = newY; bestRot = opt[3]; createdShelf = true
            )
        )
    )
    if createdShelf do return #(bestB, bestPx, bestPy, bestRot)

    local opt = undefined
    for o in sortedOpts do ( if o[1] <= binW + 0.001 and o[2] <= binD + 0.001 do ( opt = o; exit ) )
    if opt == undefined do return undefined 
    local tw = opt[1]; local th = opt[2]
    append boards #(binD - (th + gap), #( #(0.0, tw + gap, th, binW - (tw + gap)) ))
    return #(boards.count, 0.0, 0.0, opt[3])
)

fn packPieceVertical boards w d binW binD gap allowRot =
(
    local opts = if allowRot then #( #(w,d, false), #(d,w, true) ) else #( #(w,d, false) )
    if allowRot and abs(w - d) < 0.001 do opts = #( #(w,d, false) )

    local bestB = 0; local bestPx = 0.0; local bestPy = 0.0; local bestRot = false; local foundExact = false

    for opt in opts while not foundExact do
    (
        local tw = opt[1]; local th = opt[2]
        for i = 1 to boards.count while not foundExact do
        (
            local b = boards[i]
            for j = 1 to b[2].count while not foundExact do
            (
                local c = b[2][j]
                if abs(tw - c[3]) < 0.1 and th <= c[4] + 0.001 do
                (
                    bestB = i; bestPx = c[1]; bestPy = c[2]; bestRot = opt[3]
                    c[2] += th + gap; c[4] -= (th + gap); foundExact = true
                )
            )
        )
    )
    if foundExact do return #(bestB, bestPx, bestPy, bestRot)

    local foundAny = false
    for opt in opts while not foundAny do
    (
        local tw = opt[1]; local th = opt[2]
        for i = 1 to boards.count while not foundAny do
        (
            local b = boards[i]
            for j = 1 to b[2].count while not foundAny do
            (
                local c = b[2][j]
                if tw <= c[3] + 0.001 and th <= c[4] + 0.001 do
                (
                    bestB = i; bestPx = c[1]; bestPy = c[2]; bestRot = opt[3]
                    c[2] += th + gap; c[4] -= (th + gap); foundAny = true
                )
            )
        )
    )
    if foundAny do return #(bestB, bestPx, bestPy, bestRot)

    local sortedOpts = deepCopy opts
    if sortedOpts.count > 1 and sortedOpts[1][1] > sortedOpts[2][1] do ( local temp = sortedOpts[1]; sortedOpts[1] = sortedOpts[2]; sortedOpts[2] = temp )
    
    local createdCol = false
    for opt in sortedOpts while not createdCol do
    (
        local tw = opt[1]; local th = opt[2]
        for i = 1 to boards.count while not createdCol do
        (
            local b = boards[i]
            if tw <= b[1] + 0.001 and th <= binD + 0.001 do
            (
                local newX = 0.0
                if b[2].count > 0 do ( local lastC = b[2][b[2].count]; newX = lastC[1] + lastC[3] + gap )
                append b[2] #(newX, th + gap, tw, binD - (th + gap))
                b[1] -= (tw + gap)
                bestB = i; bestPx = newX; bestPy = 0.0; bestRot = opt[3]; createdCol = true
            )
        )
    )
    if createdCol do return #(bestB, bestPx, bestPy, bestRot)

    local opt = undefined
    for o in sortedOpts do ( if o[1] <= binW + 0.001 and o[2] <= binD + 0.001 do ( opt = o; exit ) )
    if opt == undefined do return undefined
    local tw = opt[1]; local th = opt[2]
    append boards #(binW - (tw + gap), #( #(0.0, th + gap, tw, binD - (th + gap)) ))
    return #(boards.count, 0.0, 0.0, opt[3])
)

-- ============================================================
-- FASE 3: MOTOR DE CORTE (Executado após selecionar fitas)
-- ============================================================
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
    local areaTotalPecas = 0.0

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

        if groupMode == 2 then qsort rects sortHeightDesc
        else if groupMode == 3 then qsort rects sortWidthDesc
        else qsort rects sortAreaDesc

        local boards = #()
        
        for item in rects do
        (
            local obj = item[1]; local w = item[2]; local d = item[3]
            
            local res = undefined
            if groupMode == 3 then res = packPieceVertical boards w d binW_Util binD_Util gap allowRot
            else res = packPieceHorizontal boards w d binW_Util binD_Util gap allowRot

            if res == undefined do continue

            local bIdx = res[1]; local px = res[2]; local py = res[3]; local rotou = res[4]

            if rotou do
            (
                local bb = nodeGetBoundingBox obj (matrix3 1)
                local cR = (bb[1]+bb[2]) * 0.5; rotate obj (angleaxis 90 [0,0,1])
                local bbR2 = nodeGetBoundingBox obj (matrix3 1); obj.pos += (cR - ((bbR2[1]+bbR2[2]) * 0.5))
                local bbZ = nodeGetBoundingBox obj (matrix3 1); obj.pos.z -= bbZ[1].z
            )

            local bbNow = nodeGetBoundingBox obj (matrix3 1)
            local ESPACO_CHAPAS = 200.0 / 25.4
            local planoOffsetY = (bIdx - 1) * (binD + ESPACO_CHAPAS)
            
            obj.pos.x += ((px + borda) + globalOffsetX - bbNow[1].x)
            obj.pos.y += ((py + borda) + planoOffsetY - bbNow[1].y)

            local actualW = abs(bbNow[2].x - bbNow[1].x); local actualD = abs(bbNow[2].y - bbNow[1].y)
            local origNameLen = obj.name.count - "_MED".count
            local nomeReal = if origNameLen > 0 then substring obj.name 1 origNameLen else obj.name
            
            local shp = Rectangle width:actualW length:actualD pos:[ (px + borda) + globalOffsetX + actualW/2.0, (py + borda) + planoOffsetY + actualD/2.0, 0 ]
            shp.name = nomeReal + "_2D"; shp.wirecolor = color 0 255 0; convertToSplineShape shp
            cncLayer.addNode shp; append shapes2D shp
        )

        for i = 1 to boards.count do
        (
            local ESPACO_CHAPAS = 200.0 / 25.4
            local planoOffsetY = (i - 1) * (binD + ESPACO_CHAPAS)
            areaTotalChapas += (binW * binD)
            totalChapasUsadas += 1
            
            local limitOut = Rectangle width:binW length:binD pos:[globalOffsetX + binW/2.0, planoOffsetY + binD/2.0, 0]
            limitOut.name = "Chapa_" + (espAtual as string) + "mm_" + (i as string); limitOut.wirecolor = color 255 0 0
            convertToSplineShape limitOut; cncLayer.addNode limitOut; append shapes2D limitOut
        )
        
        globalOffsetX += binW + (400.0 / 25.4)
    )

    -- Relatório CSV
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
    )
    
    print "\n=== LISTA DE CORTE OTIMIZADA PARA CNC/SECCIONADORA ==="
    for l in csvArr do format "%\n" l

    local aproveitamento = 0.0
    if areaTotalChapas > 0 do aproveitamento = (areaTotalPecas / areaTotalChapas) * 100.0

    if expDWG and shapes2D.count > 0 do
    (
        clearSelection(); select shapes2D
        local savePath = getSaveFileName caption:"Salvar Plano de Corte DWG" types:"AutoCAD DWG (*.dwg)|*.dwg|AutoCAD DXF (*.dxf)|*.dxf|"
        if savePath != undefined do ( exportFile savePath #noPrompt selectedOnly:true; format "Exportado DWG: %\n" savePath )
        clearSelection()
    )

    local msgFinal = "Concluido!\n\n" +
                     "- Chapas Usadas: " + (totalChapasUsadas as string) + "\n" +
                     "- Aproveitamento: " + ((((floor(aproveitamento*100))/100.0)) as string) + " %\n" +
                     "- CSV Gerado c/ Fitas de Borda\n- Espessuras separadas fisicamente!"
    messageBox msgFinal title:"Sucesso"
)

-- ============================================================
-- FASE 2: UI FITAS DE BORDA (Dinamica)
-- ============================================================
fn abrirUIFitas =
(
    local ss = stringStream ""
    format "if fltFitas != undefined do closeRolloutFloater fltFitas\n" to:ss
    format "fltFitas = newRolloutFloater \"Fitas e Acabamento\" 540 600\n" to:ss
    format "rollout rlFitas \"Aplicacao de Fitas de Borda\" width:500 (\n" to:ss
    
    -- Dropdown de Espessura
    format "  dropDownList ddFita \"Espessura da Fita (mm):\" items:#(\"0.45\", \"1.0\", \"1.5\", \"2.0\", \"3.0\") selection:2 width:150 align:#center offset:[0,10]\n" to:ss
    
    -- Linha de cabeçalho "Marcar Todas"
    format "  label lblHead \"Marcar Todas:\" across:5 align:#right offset:[10,10] width:150\n" to:ss
    format "  checkbox chkAllC1 \"C1\" align:#right offset:[0,10]\n" to:ss
    format "  checkbox chkAllC2 \"C2\" align:#left offset:[0,10]\n" to:ss
    format "  checkbox chkAllL1 \"L1\" align:#right offset:[0,10]\n" to:ss
    format "  checkbox chkAllL2 \"L2\" align:#left offset:[0,10]\n" to:ss
    
    format "  label lblLine \"-----------------------------------------------------------------------------------------------------\" align:#left offset:[10,0]\n" to:ss
    
    -- Geração da lista (agora pré-ordenada)
    for i=1 to G_PiecesData.count do
    (
        format "  label lbl_% \"%\" across:5 align:#left offset:[10,0] width:150\n" i G_PiecesData[i].nome to:ss
        format "  checkbox c1_% \"C1\" align:#right\n" i to:ss
        format "  checkbox c2_% \"C2\" align:#left\n" i to:ss
        format "  checkbox l1_% \"L1\" align:#right\n" i to:ss
        format "  checkbox l2_% \"L2\" align:#left\n" i to:ss
    )
    
    format "  button btnGo \"Confirmar e Gerar Plano\" height:40 width:480 align:#center offset:[0,20]\n" to:ss
    
    -- Eventos de Marcar Tudo
    format "  on chkAllC1 changed state do ( " to:ss
    for i=1 to G_PiecesData.count do format "c1_%.checked = state; " i to:ss
    format ")\n" to:ss
    
    format "  on chkAllC2 changed state do ( " to:ss
    for i=1 to G_PiecesData.count do format "c2_%.checked = state; " i to:ss
    format ")\n" to:ss
    
    format "  on chkAllL1 changed state do ( " to:ss
    for i=1 to G_PiecesData.count do format "l1_%.checked = state; " i to:ss
    format ")\n" to:ss
    
    format "  on chkAllL2 changed state do ( " to:ss
    for i=1 to G_PiecesData.count do format "l2_%.checked = state; " i to:ss
    format ")\n" to:ss

    -- Evento Confirmar
    format "  on btnGo pressed do (\n" to:ss
    for i=1 to G_PiecesData.count do
    (
        format "    G_PiecesData[%].c1 = c1_%.checked\n" i i to:ss
        format "    G_PiecesData[%].c2 = c2_%.checked\n" i i to:ss
        format "    G_PiecesData[%].l1 = l1_%.checked\n" i i to:ss
        format "    G_PiecesData[%].l2 = l2_%.checked\n" i i to:ss
    )
    
    format "    local fitaVals = #(0.45, 1.0, 1.5, 2.0, 3.0)\n" to:ss
    format "    G_FitaTh = fitaVals[ddFita.selection]\n" to:ss
    
    format "    closeRolloutFloater fltFitas\n" to:ss
    format "    executarMotorDeCorte()\n" to:ss
    format "  )\n" to:ss
    format ")\n" to:ss
    format "addRollout rlFitas fltFitas\n" to:ss
    
    execute (ss as string)
)

-- ============================================================
-- FASE 1: PREPARAÇÃO DAS PEÇAS E UI INICIAL
-- ============================================================
fn processarFase1 binW binD gap borda sufixo expDWG alignMode groupMode =
(
    if selection.count == 0 do ( messageBox "Nenhum objeto selecionado!" title:"Aviso"; return undefined )

    G_MainConfig = #(binW, binD, gap, borda, expDWG, alignMode, groupMode)
    G_PiecesData = #()

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
            local bb0 = nodeGetBoundingBox obj (matrix3 1)
            local centro = (bb0[1]+bb0[2]) * 0.5
            local axes = calcPCA obj
            local rotMat = buildAlignMatrix axes
            obj.transform = (inverse rotMat) * obj.transform
            local bb1 = nodeGetBoundingBox obj (matrix3 1)
            obj.pos += (centro - ((bb1[1]+bb1[2]) * 0.5))
            local bb2 = nodeGetBoundingBox obj (matrix3 1)
            obj.pos.z -= bb2[1].z
            
            local bbFinal = nodeGetBoundingBox obj (matrix3 1)
            local w = abs(bbFinal[2].x - bbFinal[1].x)
            local d = abs(bbFinal[2].y - bbFinal[1].y)
            local esp = abs(bbFinal[2].z - bbFinal[1].z)
            
            if d > w do ( local t=w; w=d; d=t )
            
            local origNameLen = obj.name.count - sufixo.count
            local nomeReal = if origNameLen > 0 then substring obj.name 1 origNameLen else obj.name
            
            append G_PiecesData (PieceObj node:obj nome:nomeReal comp:w larg:d esp:esp c1:false c2:false l1:false l2:false)
        ) catch()
    )

    -- Aqui ocorre a mágica do agrupamento natural!
    qsort G_PiecesData sortPiecesByName

    abrirUIFitas()
)

CHAPAS_NOMES = #("--- MDF ---", "MDF 1830 x 2750 mm", "MDF 1830 x 2200 mm", "MDF 1550 x 2750 mm", "MDF 1220 x 2440 mm", "--- PERSONALIZADO ---", "Personalizado")
CHAPAS_W = #( 0, 1830,1830,1550,1220, 0, 0 )
CHAPAS_D = #( 0, 2750,2200,2750,2440, 0, 0 )

fn abrirUIPrincipal =
(
    local dlg = newRolloutFloater "Plano de Corte CNC" 370 510

    rollout rlConfig "Configurações Gerais"
    (
        label lbC "Material / Tamanho da chapa:" align:#left
        dropDownList ddChapa "" items:CHAPAS_NOMES selection:2 width:340 align:#left

        label lbW "Largura Total  X  [mm]:" align:#left
        spinner spW "" range:[10,100000,CHAPAS_W[2]] type:#float fieldWidth:130 align:#left

        label lbD "Profundidade Total  Y  [mm]:" align:#left
        spinner spD "" range:[10,100000,CHAPAS_D[2]] type:#float fieldWidth:130 align:#left

        label lbG "Gap da Fresa (Espaçamento) [mm]:" align:#left
        spinner spG "" range:[0,500,5] type:#float fieldWidth:130 align:#left
        
        label lbB "Borda de Seguranca da Chapa [mm]:" align:#left
        spinner spB "" range:[0,500,15] type:#float fieldWidth:130 align:#left
        
        label lbAlign "Alinhamento (Veio da Madeira):" align:#left offset:[0, 5]
        dropDownList ddAlign "" items:#("Rotacao Livre (Melhor Sobra)", "Manter Orientacao Original", "Forcar Maior Lado na Horizontal") selection:1 width:340 align:#left

        label lbGroup "Estrategia de Alinhamento e Corte:" align:#left offset:[0, 5]
        dropDownList ddGroup "" items:#("Otimizacao Livre em Niveis", "Agrupar Tiras Horizontais (Mesma Altura)", "Agrupar Tiras Verticais (Mesma Largura)") selection:2 width:340 align:#left

        checkbox chkDWG "Exportar 2D para DWG ao finalizar" checked:true align:#left offset:[0, 5]

        button btnAvan "Avançar para Fitas de Borda >>" width:340 height:38 align:#center offset:[0, 10]

        on ddChapa selected idx do
        (
            local w=CHAPAS_W[idx]; local d=CHAPAS_D[idx]
            if w>0 and d>0 then ( spW.value=w; spD.value=d; spW.enabled=false; spD.enabled=false )
            else ( spW.enabled=true; spD.enabled=true; if CHAPAS_NOMES[idx]=="Personalizado" do ( spW.value=1830; spD.value=2750 ) )
        )

        on btnAvan pressed do
        (
            local binW   = spW.value / 25.4
            local binD   = spD.value / 25.4
            local gap    = spG.value / 25.4
            local borda  = spB.value / 25.4
            local sufixo = "_MED"
            local expDWG = chkDWG.checked
            local alignMode = ddAlign.selection
            local groupMode = ddGroup.selection
            
            if spW.value<=0 or spD.value<=0 then ( messageBox "Defina dimensoes validas." title:"Aviso"; return undefined )
            destroyDialog rlConfig
            processarFase1 binW binD gap borda sufixo expDWG alignMode groupMode
        )
    )
    addRollout rlConfig dlg
)

abrirUIPrincipal()
