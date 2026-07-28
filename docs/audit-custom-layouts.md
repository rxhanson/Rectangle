# Auditoria técnica — layouts personalizados

Data da auditoria: 2026-07-28  
Escopo: leitura do fork de Rectangle para macOS. Nenhum código de produção, identidade, configuração de Xcode ou recurso visual foi alterado.

## Resumo executivo

O projeto já tem uma base madura para redimensionar **a janela ativa** em áreas proporcionais da tela. O caminho principal é:

```text
atalho / menu / snap
  -> WindowAction.post*(NotificationCenter)
  -> ShortcutManager.execute
  -> WindowManager.execute
  -> WindowCalculationFactory + cálculo geométrico
  -> gaps / resize cooperativo (opcional)
  -> WindowMover + Accessibility API (AX)
  -> WindowHistory (restore e repetição)
```

Há suporte existente para uma razão horizontal configurável em `Left`/`Right`: `Defaults.horizontalSplitRatio` (1–99 na interface) é usado por `LeftRightHalfCalculation`. Assim, configurar 60 hoje faz `Left` ocupar 60% e `Right` 40%. Isso **não** entrega os layouts solicitados como ações independentes: muda o significado global de Left/Right, influencia cantos e ciclos, e não permite manter 60/40, 70/30 e 80/20 acessíveis simultaneamente.

O menor MVP seguro é adicionar seis ações estáticas, cada uma calculando somente a janela ativa dentro de `NSScreen.adjustedVisibleFrame()`, sem alterar `horizontalSplitRatio`, sem resize cooperativo e sem tentar encontrar a segunda janela. A melhor base geométrica para isso é `HalfSplitFrameCalculation.horizontalRect(in:side:fraction:)`.

## 1. Arquitetura geral

O app principal é o target `Rectangle`; há também o target auxiliar `RectangleLauncher`. O ciclo de vida e a composição de serviços ficam em `Rectangle/AppDelegate.swift`:

- `accessibilityTrusted()` instancia `WindowManager`, `ShortcutManager`, `SnappingManager`, `TitleBarManager`, `GreenButtonManager` e outros serviços após a autorização de Acessibilidade.
- `WindowAction` é o catálogo central de comandos. Ele contém identificador persistente, nome, rótulo localizado, ícone, atalhos padrão, categoria e metadados de comportamento.
- `ShortcutManager` converte eventos de ações em execução de janela; fontes alternativas (menu, snap, URL e título) publicam a mesma notificação.
- `WindowManager` é o orquestrador da execução: encontra a janela ativa via AX, escolhe tela, mantém histórico, calcula o alvo, aplica gaps/ajustes e move a janela.
- `WindowCalculation/` contém cálculos de geometria, em geral puros e testáveis, indexados por `WindowCalculationFactory.calculationsByAction`.
- `WindowMover/` aplica o resultado, trata janelas não redimensionáveis ou que o macOS limita e reposiciona resultados que não caibam na área útil.
- `ScreenDetection` e a extensão de `NSScreen` resolvem tela ativa, ordem de monitores e área útil.
- `PrefsWindow/` contém preferências, gravação de atalhos e importação/exportação. A UI híbrida é storyboard (`Rectangle/Base.lproj/Main.storyboard`) mais controles montados por código em `SettingsViewController`.
- `Snapping/`, `MultiWindow/` e `TodoMode/` são recursos paralelos, fora do MVP mas integrados ao mesmo modelo de ações.

Dependências relevantes visíveis no código: Cocoa/AppKit, Carbon, MASShortcut (atalhos), Sparkle (updates) e APIs de Accessibility (`AXUIElement`).

## 2. Diretórios, módulos e responsabilidades

| Área | Arquivos/símbolos principais | Responsabilidade |
| --- | --- | --- |
| Bootstrap/UI de status | `AppDelegate.swift`, `RectangleStatusItem.swift`, `Base.lproj/Main.storyboard` | Inicialização, autorização, menu da barra, janela de preferências. |
| Catálogo de comandos | `WindowAction.swift`, `WindowActionCategory.swift`, `WindowActionCooperativeResize.swift` | Enum de ações e sua apresentação/classificação. |
| Execução | `ShortcutManager.swift`, `WindowManager.swift` | Registro/dispatch de comandos, seleção da janela/tela, histórico e pós-processamento. |
| Geometria | `WindowCalculation/WindowCalculation.swift` e subclasses | Cálculo de `CGRect` em coordenadas normalizadas; factory de cálculos. |
| Aplicação via AX | `AccessibilityElement.swift`, `WindowMover/*.swift` | Leitura/escrita de frame, mínima dimensão, tolerância a restrições de apps. |
| Telas | `ScreenDetection.swift`, `Utilities/CGExtension.swift`, `Utilities/StageUtil.swift` | Tela corrente, área visível e transformação de coordenadas. |
| Estado/preferências | `Defaults.swift`, `ActiveSideSplitRatios.swift`, `WindowHistory.swift`, `CycleSize.swift` | `UserDefaults`, razão dinâmica por tela, restore e ciclos. |
| Preferências/configuração | `PrefsWindow/*.swift` | Atalhos, opções, razão de split e JSON de import/export. |
| Snap e multi-janela | `Snapping/`, `MultiWindow/`, `TodoMode/` | Snap por arrasto, footprints, operações em várias janelas e sidebar Todo. |
| Testes | `RectangleTests/RectangleTests.swift`, `ShortcutRecordingObserverTests.swift` | Geometria, ciclos, gaps, resize cooperativo e atalhos. |

## 3. Declaração das ações e fluxo até o frame final

### Declaração e registro

`Rectangle/WindowAction.swift` declara `enum WindowAction: Int, Codable`. Os casos são numerados explicitamente e `WindowAction.active` define a ordem canônica usada por menus, defaults de atalhos, observadores e import/export. Para cada ação, o mesmo arquivo fornece:

- `name`, usado como chave de `UserDefaults` e `Notification.Name`;
- `displayName`, `image`, `category`, `firstInGroup` e `gapSharedEdge`;
- `spectacleDefault`/`alternateDefault`;
- `resizes`, `gapsApplicable`, `positionCycles` e `isDragSnappable`.

`WindowAction.post()`, `postMenu()`, `postSnap(...)`, `postUrl()` e `postTitleBar(...)` publicam `ExecutionParameters` no `NotificationCenter` com a origem apropriada.

`ShortcutManager.init` percorre `WindowAction.active`, registra os atalhos padrão com `MASShortcutBinder`, associa os bindings e se inscreve em todas as notificações. `ShortcutManager.execute(_:)` pode delegar primeiro a `MultiWindowManager` ou `TodoManager`; caso contrário chama `WindowManager.execute(_:)`.

### Cálculo e aplicação

1. `WindowManager.execute(_:)` obtém `AccessibilityElement.getFrontWindowElement()` e o `CGWindowID`; `restore` é um caso especial tratado antes do cálculo.
2. Determina `UsableScreens` com `ScreenDetection`: tela da janela ou, quando configurado, tela sob o cursor.
3. Lê o frame AX da janela, o converte para coordenadas normalizadas (`screenFlipped`), recupera histórico e, para ações normais, salva o frame inicial de restore se necessário.
4. Busca `WindowCalculationFactory.calculationsByAction[action]` e chama `calculate(WindowCalculationParameters)`.
5. Aplica `GapCalculation.applyGaps`, offset de sobreposição e, se habilitado, planejamento de resize cooperativo de cantos/laterais.
6. Aplica o frame pela cadeia `StandardWindowMover`, `EdgeAlignmentWindowMover`, `BestEffortWindowMover`; para janelas fixas usa `FixedSizeWindowMover` e `BestEffortWindowMover`.
7. Registra a ação final em `WindowHistory.lastRectangleActions` e pode mover o cursor conforme preferências.

O contrato de cálculo é definido em `WindowCalculation/WindowCalculation.swift`:

- `WindowCalculationParameters` inclui janela, telas, ação, última ação e contexto Todo;
- `RectCalculationParameters` contém a `visibleFrameOfScreen` que efetivamente delimita o cálculo;
- `RectResult` e `WindowCalculationResult` carregam frame e subação;
- `WindowCalculationFactory` mantém instâncias e o mapa ação → cálculo.

## 4. Implementação atual das ações pedidas

Todos os cálculos abaixo usam a área útil recebida em `RectCalculationParameters.visibleFrameOfScreen`. Em modo landscape, os terços são horizontais; em tela portrait, os cálculos de terceiros passam a ser verticais por `OrientationAware.orientationBasedRect(_:)`.

| Ação | Declaração/dispatch | Cálculo atual | Comportamento relevante |
| --- | --- | --- | --- |
| Left Half | `.leftHalf`, `LeftRightHalfCalculation` | `calculateFirstRect` lê `ActiveSideSplitRatios.horizontalRatio`; usa a fração à esquerda e `HalfSplitFrameCalculation.horizontalRect(..., .leading, ...)`. | Padrão 50%, mas a preferência permite 1–99; execuções repetidas podem redimensionar/circular ou atravessar telas conforme `subsequentExecutionMode`. |
| Right Half | `.rightHalf`, mesma classe | Usa fração complementar (`1 - ratio`), lado `.trailing`; a origem é `visible.maxX - width`. | Com 60 configurado, resulta em 40% à direita. Repetição pode atravessar à próxima tela. |
| First Third | `FirstThirdCalculation` | Landscape: `width = floor(visible.width / 3)` na borda esquerda. Portrait: `height = floor(visible.height / 3)` no topo. | Pode ciclar First → Center → Last quando `subsequentExecutionMode != .none` e o histórico/subação é compatível. |
| Center Third | `CenterThirdCalculation` | Landscape: `x = minX + floor(width / 3)`, `width = width / 3`. Portrait: equivalente vertical. | Não arredonda a dimensão central, diferentemente dos extremos; isso é deliberado/legado. |
| Last Third | `LastThirdCalculation` | Landscape: `width = floor(width / 3)`, `x = maxX - width`. Portrait: um terço inferior. | Pode ciclar Last → Center → First a partir do histórico. |
| First Two Thirds | `FirstTwoThirdsCalculation` | Landscape: `width = floor(width * 2 / 3)` alinhado à esquerda. Portrait: 2/3 no topo. | Ao repetir o mesmo lado, alterna para `LastTwoThirdsCalculation`. |
| Last Two Thirds | `LastTwoThirdsCalculation` | Landscape: `width = floor(width * 2 / 3)`, `x = maxX - width`. Portrait: 2/3 inferiores. | Ao repetir, alterna para os primeiros 2/3. |
| Maximize | `MaximizeCalculation` | Retorna integralmente `visibleFrameOfScreen`. | Pode receber gaps, salvo se `Defaults.applyGapsToMaximize` for explicitamente desabilitado. Não é o full-screen nativo do macOS. |
| Restore | `.restore` em `WindowManager.execute(_:)` | Não há `WindowCalculation`: lê `AppDelegate.windowHistory.restoreRects[windowId]`, chama `AccessibilityElement.setFrame(_:)` e remove somente `lastRectangleActions`. | O restore é memória de processo, por ID da janela; não sobrevive relaunch e não é persistido. |

## 5. Área útil, monitores, escala e coordenadas

### Área útil, menu bar e Dock

O ponto de partida é `NSScreen.visibleFrame` em `NSScreen.adjustedVisibleFrame(_:_)`, em `ScreenDetection.swift`. AppKit fornece esse frame em pontos, excluindo as regiões de sistema ocupadas, portanto normalmente considera menu bar e Dock (inclusive Dock lateral). O app então ajusta esse frame para:

- Stage Manager, quando detectado e configurado: desconta a faixa Stage à esquerda quando visível;
- Todo Mode: desconta a sidebar interna do Rectangle;
- screen edge gaps configurados (incluindo tratamento diferenciado para notch com `safeAreaInsets.top`);
- combined display mode, quando Spaces separadas não estão em uso.

Consequência: os layouts devem sempre ser calculados sobre `adjustedVisibleFrame`, nunca sobre `NSScreen.frame`, para preservar menu bar, Dock e margens existentes.

### Vários monitores

`ScreenDetection.detectScreens(using:)` atribui a janela à tela que a contém por inteiro ou àquela que cobre a maior área dela. `detectScreensAtCursor()` suporta a preferência de localizar pela tela sob o cursor. `order(screens:)` aplica `Defaults.screensOrderedByX` e `adjacent(...)` determina anterior/próxima para comandos de display. Ações Left/Right têm semântica adicional de atravessar telas em `LeftRightHalfCalculation.calculateAcrossDisplays(_:)` quando o modo de execução subsequente o pede.

Para um layout novo de 60/40 independente, o MVP não deve copiar essa travessia: deve simplesmente usar a tela escolhida por `WindowManager`, o que mantém o escopo "janela ativa" e reduz regressões.

### Escalas, resolução, orientação e eixos

- Os frames de AppKit são expressos em pontos (`CGFloat`), por isso a geometria não deve assumir pixels físicos ou `backingScaleFactor`.
- `CGRect.screenFlipped` em `Utilities/CGExtension.swift` converte entre a convenção de tela normalizada usada nos cálculos (origem inferior esquerda) e a convenção AX (origem superior esquerda). A altura de referência é `NSScreen.screens[0].frame.maxY`; coordenadas negativas ainda são preservadas e têm testes.
- A aplicação AX ocorre em `StandardWindowMover` com `rect.screenFlipped`; `AccessibilityElement.setFrame` escreve tamanho/posição separadamente porque AX não aceita uma alteração atômica de frame.
- `OrientationAware` troca automaticamente terceiros para o eixo vertical em portrait. Os layouts 60/40 solicitados são explicitamente esquerda/direita, portanto o MVP deve permanecer horizontal mesmo em monitores portrait — outra razão para não reutilizar diretamente os cálculos de terceiros.
- `HalfSplitFrameCalculation` faz `floor(value + 0.0001)` para dimensões proporcionais e ancora a parte trailing por `maxX - width`, estratégia apropriada para evitar ultrapassar a borda por ponto fracionário.

## 6. Atalhos, menu e preferências

### Atalhos

`ShortcutManager.registerDefaults()` registra um `MASShortcut` por ação em `WindowAction.active`, com a chave `WindowAction.name`. `PrefsWindow/PrefsViewController.swift` mapeia as ações usuais para `MASShortcutView`; configurações adicionais criam campos equivalentes em `SettingsViewController`. Ao gravar um atalho, `ShortcutRecordingObserver` suspende temporariamente os bindings para evitar disparo durante a captura.

Atalhos iguais não são recusados: `ShortcutCycle.groups(...)` agrupa ações de mesma combinação seguindo a ordem de `WindowAction.active`, e `executeCycle(_:)` executa a próxima ação do grupo baseado no histórico da janela. Isso é útil, mas uma nova ação deve ser adicionada à lista ativa numa posição consciente para não mudar a ordem de ciclos já existentes.

### Menu da barra de menus

`AppDelegate.addWindowActionMenuItems()` percorre `WindowAction.active`, cria `NSMenuItem` com `displayName`, armazena a ação em `representedObject` e chama `executeMenuWindowAction(sender:)`, que usa `postMenu()`. `WindowAction.category` e `WindowActionCategory` organizam submenus; `firstInGroup` determina separadores. `menuWillOpen`/`updateWindowActionMenuItems(menu:)` aplicam ícones e o equivalente de teclado atual. `showAllActionsInMenu` e `showAdditionalSizesInMenu` controlam agrupamento/visibilidade.

### Persistência

`Defaults.swift` encapsula `UserDefaults.standard` em tipos `BoolDefault`, `OptionalBoolDefault`, `FloatDefault`, `IntDefault`, `IntEnumDefault` e `JSONDefault`. As chaves exportáveis ficam em `Defaults.array`.

Recursos existentes que se relacionam a layouts:

- `Defaults.horizontalSplitRatio` e `verticalSplitRatio`, ambos `FloatDefault` com default 50;
- `ActiveSideSplitRatios`: estado **em memória**, por frame de display, que acompanha mudanças alcançadas por resize cooperativo/ciclo; não é persistido;
- `Defaults.specifiedWidth` / `specifiedHeight` e `SpecifiedCalculation`: tamanho absoluto (pontos) ou proporcional (valor `<= 1`), centralizado;
- `CycleSize`/`selectedCycleSizes`: presets de 1/3, 1/2, 2/3, 1/4 e 3/4 para ciclos de ações existentes.

`SettingsViewController` expõe a razão horizontal/vertical em “Extra Settings”: o menu predefinido contém somente os valores de `CycleSize`, mas o campo “Other” aceita inteiro de 1 a 99. Ao mudar a razão, `ActiveSideSplitRatios.resetAll()` é chamado.

## 7. Suporte já existente versus o que falta

| Capacidade | Estado | Evidência e avaliação |
| --- | --- | --- |
| Split ratio | **Existe, mas global** | `horizontalSplitRatio` é aplicado por `LeftRightHalfCalculation` e por cálculos de canto. Serve para um único split configurado, não para layouts simultâneos e nomeados. |
| Tamanho configurável | **Existe** | `.specified` + `SpecifiedCalculation`; é centrado e não representa ancoragem esquerda/direita. |
| Layouts especificados por fração | **Parcial** | Há halves, thirds, fourths, sixths, eighths, ninths, twelfths e sixteenths como ações fechadas. Não há 60/40, 70/30 ou 80/20 nomeados. |
| Presets | **Parcial** | `CycleSize` oferece 1/4, 1/3, 1/2, 2/3 e 3/4 para ciclo/ratio global. Não há coleção persistida de presets de layouts independentes. |
| Ações customizadas genéricas | **Não** | `WindowAction` é enum fechado e o factory é um dicionário estático. Não existe DSL, modelo de layout ou ações definidas pelo usuário. |
| Import/export | **Existe para defaults e atalhos** | `PrefsWindow/Config.swift` serializa `Config` JSON; não há schema de layouts porque ainda não existe essa entidade. |

**Reaproveitar:** `HalfSplitFrameCalculation`, `WindowCalculation`/factory, `WindowManager`, AX movers, gaps, histórico de restore, `MASShortcut`, menu dinâmico, `Defaults` e testes de razão/arre­dondamento.

**Criar:** novas ações semânticas, cálculo horizontal de proporção fixa por ação, metadados de menu/atalho/ícone, UI de atalhos e testes próprios. Para uma fase posterior de layouts editáveis, criar um modelo persistível de layout/predefinição.

**Não alterar inicialmente:** bundle/target/scheme/ícone/nome; `horizontalSplitRatio` existente; regras de snap; `ActiveSideSplitRatios`; resize cooperativo; seleção de segunda janela; importação de configuração; e a semântica de ações existentes.

## 8. Importação e exportação

`Defaults.encoded()` em `PrefsWindow/Config.swift` cria JSON `Config` com `bundleId`, versão do bundle, dicionário de atalhos e dicionário de defaults exportáveis. Apenas `WindowAction.active` e as chaves Todo são incluídos nos atalhos. A UI em `SettingsViewController.exportConfig(_:)` usa `NSSavePanel` e grava JSON.

`Defaults.load(fileUrl:)` limita arquivo a 1 MiB, decodifica JSON, aplica somente chaves presentes em `Defaults.array`, importa atalhos conhecidos (incluindo aliases de ações renomeadas) e publica `.configImported`. `AppDelegate` recarrega os serviços dependentes da configuração. `loadFromSupportDir()` trata um arquivo de Application Support com confirmação explícita, rejeita symlink/arquivo world-writable e arquiva/remove o arquivo após a decisão.

Para a fase de ações fixas do MVP, os novos atalhos serão automaticamente exportados/importados quando as ações entrarem em `WindowAction.active`. Se forem criados presets editáveis posteriormente, seu `Codable` deve ser adicionado a `Defaults.array` ou, melhor, a um campo JSON versionado próprio; não se deve depender apenas do `bundleId` atual como validação de compatibilidade.

## 9. Cobertura de testes existente

Os testes estão centralizados em `RectangleTests/RectangleTests.swift` (mais `ShortcutRecordingObserverTests.swift`). Cobertura diretamente reaproveitável:

- `ScreenFlippedTests`: inversão, preservação de tamanho/X, `CGRect.null` e coordenadas negativas;
- `HalfSplitCornerCalculationTests.testHalfActionsStillUseHalfSplitRatio`, `testCornersUseCustomHalfSplitRatio` e testes de repetição: frações 50/60/2/3/3/4, ancoragem e ciclos;
- `CycleSizeRatioPresetTests`: equivalência/tolerância de presets;
- `ActiveSideSplitRatiosCooperativeTests`: razão por tela, comportamento após constraints e gaps;
- `CooperativeCornerResizeTests`: mínimos, vizinhos, gaps, arredondamento e estabilização AX;
- `ClampedWindowAlignerTests`: ancoragem/centralização de janelas que não atingem o tamanho pedido;
- `NilWindowIdCalculationTests`: geometria não depende de `CGWindowID`;
- `ShortcutCycleTests` e `ShortcutRecordingObserverTests`: agrupamento de atalhos e gravação.

Não há, no que foi encontrado, testes automatizados de integração que materializem `NSScreen.visibleFrame` com Dock nas quatro posições, menu bar real, Stage Manager real, monitores com escalas distintas ou a UI de menu/preferências para uma nova ação. Esses casos exigem validação manual/integração no macOS além dos unit tests puros.

## 10. Arquivos que uma implementação futura precisará alterar

Para seis ações independentes (60% esquerda, 40% direita, 70% esquerda, 30% direita, 80% esquerda, 20% direita), a lista mínima provável é:

| Arquivo | Mudança futura |
| --- | --- |
| `Rectangle/WindowAction.swift` | Declarar as seis ações com novos raw values sem renumerar casos existentes; inserir em `active`; fornecer `name`, `displayName`, `image`, `gapSharedEdge`, `gapsApplicable`, categoria e defaults de atalho (ou nenhum padrão). |
| `Rectangle/WindowCalculation/WindowCalculation.swift` | Instanciar o cálculo e mapear as seis ações em `calculationsByAction`. |
| Novo `Rectangle/WindowCalculation/FixedHorizontalSplitCalculation.swift` (recomendado) | Um cálculo parametrizado por `side` e fração, que delega a `HalfSplitFrameCalculation.horizontalRect`. Alternativamente, uma classe por ação, mas isso duplicaria código. |
| `Rectangle/PrefsWindow/PrefsViewController.swift` e `Rectangle/Base.lproj/Main.storyboard` | Adicionar campos de gravação de atalho à UI principal, ou escolher deliberadamente a seção dinâmica “Extra Shortcuts”. |
| `Rectangle/PrefsWindow/SettingsViewController.swift` | Se os controles forem criados dinamicamente, criar os `MASShortcutView` e associá-los às novas chaves. |
| `Rectangle/Assets.xcassets/WindowPositions/*` | Acrescentar ícones de menu se a UI precisar de ícones distintos. Para preservar o escopo, é aceitável começar com um ícone existente/empty image somente se isso for coerente com a UI vigente; não é trabalho de rebranding. |
| `Rectangle/mul.lproj/Main.xcstrings` | Acrescentar traduções/strings localizadas de `displayName` e preferências. |
| `Rectangle.xcodeproj/project.pbxproj` | Registrar o novo arquivo Swift no grupo e no build phase, pois o projeto usa referências explícitas. |
| `RectangleTests/RectangleTests.swift` | Cobrir a geometria, metadados e regressões descritas na seção seguinte. |

`AppDelegate.swift`, `ShortcutManager.swift`, `WindowManager.swift`, `ScreenDetection.swift`, `Defaults.swift`, `ActiveSideSplitRatios.swift`, `WindowMover/*` e `Config.swift` **não precisam mudar no primeiro MVP** se as novas ações forem estáticas, sem preferência nova e sem comportamento cooperativo especial. Os novos atalhos passam pelo fluxo genérico por estarem em `WindowAction.active`; import/export os inclui pelo mesmo motivo.

## 11. Estruturas novas recomendadas

### MVP: profunda e pequena

Criar uma estrutura não persistida, por exemplo:

```swift
struct FixedHorizontalSplit {
    let side: HalfSplitSide
    let fraction: Float
}
```

e uma única `FixedHorizontalSplitCalculation` que recebe a especificação no inicializador. O cálculo deve retornar `HalfSplitFrameCalculation.horizontalRect(in:side:fraction:)` e não depender de `Defaults.horizontalSplitRatio` nem de `ActiveSideSplitRatios`. Isso mantém o módulo de cálculo pequeno, explícito e testável.

### Evolução pós-MVP: layouts configuráveis

Se houver intenção real de layouts editáveis, introduzir uma entidade `CustomLayoutPreset: Codable, Identifiable` separada de `WindowAction`, com pelo menos `id`, `name`, `axis`, `side`, `fraction` e versão/schema. Uma camada de resolução pode mapear uma ação estável para um preset estável. Não é recomendável tentar transformar imediatamente o `enum WindowAction` em uma enum com associated values: o enum hoje é usado como raw value `Int`, `Codable`, chave de defaults, notificação e item de menu.

## 12. Riscos técnicos e mitigação

| Risco | Impacto | Mitigação para o MVP |
| --- | --- | --- |
| Tamanho mínimo imposto pelo app | Uma janela pode não atingir 20%, 30% ou 40%; AX pode devolver frame maior. | Reutilizar `EdgeAlignmentWindowMover`/`BestEffortWindowMover`; testar uma zona pequena com frame maior; não prometer divisão perfeita. |
| `minimumSize` ausente/incorreto | Apps frequentemente não reportam mínimo; o resize cooperativo tem heurísticas extras. | Não habilitar lógica cooperativa para os novos layouts no MVP; confiar no resultado AX e no alinhador existente. |
| Múltiplos monitores e frames negativos | Cálculo pode ir para a tela errada ou inverter Y inadequadamente. | Usar somente `WindowManager` + `adjustedVisibleFrame`; testar frames com origem positiva/negativa e não calcular com `NSScreen.main`. |
| Stage Manager | A faixa visível pode reduzir largura dinamicamente. | Manter `adjustedVisibleFrame`; testar `RectCalculationParameters` com largura já reduzida. Validar manualmente com Stage Manager ligado/desligado. |
| Dock oculto ou lateral/menu bar | `visibleFrame` pode variar durante a interação e Dock lateral muda `minX`/`maxX`. | Nunca usar suposições de origem zero; testar frame com origem X/Y não nula e confirmar manualmente as posições do Dock. |
| Apps especiais/janelas fixas | Diálogos, sheets, apps com aspect ratio ou Enhanced UI podem ignorar o destino. | `WindowManager` já recusa sheets e usa cadeia especial para fixed-size/system dialogs; manter o caminho. Testar ao menos uma janela não redimensionável manualmente. |
| Tela cheia nativa | A janela pode não ser movimentável ou a semântica do usuário pode ser inesperada. | Não sair de full screen nem adicionar comportamento oculto. Validar a falha/no-op nativo; documentar como não suportado se AX recusar. |
| Restore | Novo comando atualiza a restore rect como qualquer ação normal; app mínimo pode alterar tamanho antes do restore. | Não alterar `WindowHistory`; testar que uma ação nova seguida de Restore volta ao frame inicial no mesmo processo. |
| Gaps | O gap é aplicado após a fração; a largura visual final é menor que 60%, mas a fronteira lógica é a correta. | Manter `gapsApplicable = .both` e a borda compartilhada oposta; testar gap 0 e >0. |
| Arredondamento/pontos fracionários | Frações como 0,7 em larguras ímpares podem deixar 1 ponto de diferença se ambos os lados forem calculados independentemente. | Usar `floor` na largura e ancorar trailing por `maxX - width`, exatamente como `HalfSplitFrameCalculation`; testar larguras ímpares e escala Retina. |
| Ciclo e atalhos duplicados | Incluir a ação em posição errada pode modificar a sequência de um atalho duplicado. | Definir ordem de `active` e testar `ShortcutCycle.groups` com ações novas. Para o MVP, `positionCycles` deve ser `false` ou ser explicitamente projetado; não herdar ciclo por acidente. |
| Razão global existente | Reusar `leftHalf/rightHalf` mudaria ações, cantos e usuários atuais. | Criar ações novas e fixas; não tocar em `horizontalSplitRatio`, `CycleSize` ou `ActiveSideSplitRatios`. |

## 13. Menor MVP tecnicamente seguro

Proposta: seis comandos de primeira classe, apenas sobre a janela focada:

- 60% Left e 40% Right;
- 70% Left e 30% Right;
- 80% Left e 20% Right.

Cada comando calcula a largura com base na área útil da tela atual, preserva toda a altura útil e ancora na borda solicitada. Não escolhe, move, redimensiona ou coordena uma segunda janela. O frame complementar é apenas uma consequência geométrica, não um estado de layout de duas janelas.

Decisões de segurança do MVP:

- frações codificadas nas ações, sem tela de edição de ratios;
- nenhum uso de `ActiveSideSplitRatios` ou de ciclos de `Left/Right`;
- `positionCycles = false` para que repetir o atalho seja idempotente;
- gaps consistentes com halves (`.both` e a borda interna apropriada);
- atalhos inicialmente sem default para evitar colisões, mas disponíveis para gravação pelo usuário;
- menu e preferências apenas depois de o cálculo/testes estarem corretos, ainda na mesma etapa de integração; sem alteração de assets se a decisão de produto não os exigir.

## 14. Plano incremental e testes por etapa

1. **Caracterizar o comportamento existente (sem funcionalidade nova).**
   - Adicionar/confirmar testes de caracterização para `leftHalf/rightHalf` com `horizontalSplitRatio = 60`, incluindo o fato de que cantos também mudam. Isso protege contra a tentação de reaproveitar a preferência global.
   - Testar `HalfSplitFrameCalculation.horizontalRect` em largura ímpar, origem X não zero e frações 0,2/0,3/0,4/0,6/0,7/0,8.

2. **Adicionar a geometria pura das seis ações.**
   - Criar `FixedHorizontalSplitCalculation` e os seis casos/mapeamentos de `WindowAction`.
   - Testes: frame exato para 60/40, 70/30 e 80/20; bordas `minX`/`maxX`; altura integral; complementos que se encontram sem overlap; origem negativa; tela portrait (continua horizontal); `CGRect.null`/ID nulo conforme contratos existentes.

3. **Integrar metadados de execução.**
   - Definir `gapsApplicable`, `gapSharedEdge`, `resizes`, `positionCycles` e nomes localizados; incluir em `active` e factory.
   - Testes: `gapsApplicable` e a redução de gap em ambos os lados; `positionCycles == false`; ação é resolvida pelo factory; atalho ausente não impede cálculo.

4. **Integrar UI de atalho e menu.**
   - Expor as ações no menu e na tela de atalhos, sem atalhos padrão inicialmente; incluir assets/localização somente conforme necessário.
   - Testes: `ShortcutCycle.groups` preserva ordem quando o usuário atribui mesma tecla; teste de unidade de `displayName` não nulo e, se extraído para método testável, composição do menu. Fazer smoke test manual de menu/atalho real.

5. **Validar aplicação real e restore.**
   - Sem mudar algoritmo, testar manualmente com app redimensionável, app com mínimo grande, monitor interno/externo, Dock oculto/esquerdo/direito, menu bar secundária e Stage Manager.
   - Teste automatizado onde viável para `ClampedWindowAligner` com uma zona 20–40% e uma janela maior; teste de `WindowHistory`/`WindowManager` isolável para preservar restore.

6. **Somente após estabilizar: preferências/presets configuráveis.**
   - Introduzir o modelo `CustomLayoutPreset`, migration/versionamento de JSON, UI de edição e cobertura de import/export. Não combinar esta etapa com o MVP estático.

## Conclusão

O fork já oferece o núcleo correto para o primeiro objetivo: cálculo por área útil, execução na janela ativa, integração de atalhos/menu e defesa razoável contra limites AX. O maior risco de regressão não é a matemática de 60/40; é reutilizar a razão global de Left/Right e, com isso, alterar ciclos, cantos e preferências existentes. A implementação incremental deve isolar os novos layouts como ações estáticas e testar sua geometria antes de introduzir presets ou coordenação entre janelas.
