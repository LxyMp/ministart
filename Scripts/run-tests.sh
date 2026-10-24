#!/bin/bash
# The test suite: each harness compiles the shipped sources it guards. See docs/testing.md.

set -uo pipefail

# Absolute: the workers re-enter this script after the cd, where a relative $0 would not resolve.
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
cd "$(dirname "$0")/.." || exit 1

BIN="${TMPDIR:-/tmp}/ministart-harness"
mkdir -p "$BIN"

# `--exec` is the worker half: xargs re-enters here once per queued harness.
if [ "${1:-}" = "--exec" ]; then
    shift
    name=$1 opt=$2
    shift 2
    : > "$BIN/$name.running"
    trap 'rm -f "$BIN/$name.running" "$BIN/$name.time"' EXIT
    fail() {
        printf '\033[31mFAIL\033[0m  %-25s %s\n' "$name" "$1"
        : > "$BIN/$name.failed"
        exit 0
    }
    TIMEFORMAT=%1R
    if ! compiled=$( { time swiftc -swift-version 6 "$opt" "$@" "Tests/$name.swift" -o "$BIN/$name" > "$BIN/$name.log" 2>&1; } 2>&1 ); then
        fail "did not compile"
    fi
    { time "$BIN/$name" > "$BIN/$name.log" 2>&1; } 2> "$BIN/$name.time" &
    pid=$!
    # macOS ships no `timeout`, so the worker polls; a wedged harness must fail, not stall.
    ticks=0
    while kill -0 "$pid" 2>/dev/null; do
        if [ "$ticks" -ge $((MINISTART_TEST_TIMEOUT * 5)) ]; then
            { pkill -KILL -P "$pid"; kill -KILL "$pid"; wait "$pid"; } 2>/dev/null
            printf '\n[run-tests] killed after %ss without finishing\n' "$MINISTART_TEST_TIMEOUT" >> "$BIN/$name.log"
            fail "timed out after ${MINISTART_TEST_TIMEOUT}s"
        fi
        ticks=$((ticks + 1))
        sleep 0.2
    done
    wait "$pid"
    status=$?
    took=$(< "$BIN/$name.time")
    if [ "$status" -gt 128 ]; then fail "crashed (signal $((status - 128))) after ${took}s"; fi
    if [ "$status" -ne 0 ]; then fail "assertion failed after ${took}s"; fi
    printf '\033[32mok\033[0m    %-25s %5ss  \033[2m(compile %ss)\033[0m\n' "$name" "$took" "$compiled"
    exit 0
fi

QUEUE="$BIN/queue"
EXCLUSIVE_QUEUE="$BIN/exclusive-queue"
: > "$QUEUE"
: > "$EXCLUSIVE_QUEUE"
rm -f "$BIN"/*.failed "$BIN"/*.running

failed=()
ran=0
only="${1:-}"

# `--index` feeds harness compile commands to .compile, as xcodebuild never compiles Tests/.
emit_db=0
DB="${TMPDIR:-/tmp}/ministart-compile-db.json"
if [ "$only" = "--index" ]; then
    emit_db=1
    only=""
    printf '[' > "$DB"
fi

# `slow` dispatches in the first wave; `index` only claims editor flags for a hand-run harness.
run() {
    local opt=-Onone pri=1 index_only=0 queue="$QUEUE"
    while :; do
        case "$1" in
            slow)  pri=0; shift;;
            exclusive) queue="$EXCLUSIVE_QUEUE"; shift;;
            -O)    opt=-O; shift;;
            index) index_only=1; shift;;
            *)     break;;
        esac
    done
    local name=$1
    shift
    if [ -n "$only" ] && [ "$name" != "$only" ]; then return 0; fi
    if [ "$index_only" -eq 1 ] && [ "$emit_db" -eq 0 ]; then return 0; fi
    ran=$((ran + 1))

    # Absolute paths: sourcekit-lsp ignores `directory` for relative arguments and indexes nothing.
    if [ "$emit_db" -eq 1 ]; then
        local sources=()
        for source in "$@" "Tests/$name.swift"; do sources+=("$PWD/$source"); done
        [ "$ran" -gt 1 ] && printf ',' >> "$DB"
        printf '{"directory":"%s","command":"swiftc -swift-version 6 -sdk %s' \
            "$PWD" "$(xcrun --show-sdk-path --sdk macosx)" >> "$DB"
        printf ' %s' "${sources[@]}" >> "$DB"
        # Only `Tests/` files: `.compile` is last-wins, so a shipped source keeps the app's command.
        local claimed=""
        for source in "${sources[@]}"; do
            case "$source" in *"/Tests/"*) claimed="$claimed${claimed:+,}\"$source\"";; esac
        done
        printf '","files":[%s]}' "$claimed" >> "$DB"
        return 0
    fi

    # xargs splits the queue on whitespace, so no harness source path may contain a space.
    printf '%s %s %s %s\n' "$pri" "$name" "$opt" "$*" >> "$queue"
}

L=Ministart/Features/Launcher/Model
run slow -O fuzz-test      $L/SearchRelevance.swift $L/ScriptRomanization.swift \
                           $L/LauncherMatch.swift $L/EntryNaming.swift $L/LauncherOrder.swift \
                           $L/LauncherRankingStore.swift $L/LauncherSuggestions.swift
FS=Ministart/Features/FileSearch
FILE_INDEX="$FS/Service/FileIndex.swift $FS/Service/FileIndexSnapshot.swift $FS/Service/FileIndexCrawler.swift"
run file-search-test       $FS/Model/*.swift
run file-index-test        $FS/Model/*.swift $FILE_INDEX
run file-search-session-test $FS/Model/*.swift $FS/Service/FileSearchSession.swift $FILE_INDEX
run index file-search-performance $FS/Model/*.swift $FILE_INDEX
run ranking-test           $L/SearchRelevance.swift $L/ScriptRomanization.swift \
                           $L/LauncherMatch.swift $L/LauncherRankingStore.swift
run scopes-test            $L/SearchScopes.swift
run app-name-test          Ministart/Platform/AppDisplayName.swift \
                           Ministart/Platform/BundleLocalization.swift \
                           $L/SearchRelevance.swift
run favorites-test         $L/FavoriteSlots.swift
run app-installation-test  $L/SearchRelevance.swift $L/ScriptRomanization.swift \
                           $L/LauncherMatch.swift $L/EntryNaming.swift $L/LauncherOrder.swift \
                           $L/LauncherRankingStore.swift $L/LauncherSuggestions.swift $L/SearchScopes.swift \
                           Ministart/Features/Launcher/Service/AppIndex.swift \
                           Ministart/Features/Launcher/Service/AppLauncher.swift \
                           Ministart/Features/Launcher/Service/RunningAppsMonitor.swift \
                           Ministart/Features/Launcher/Service/FavoritesStore.swift \
                           Ministart/Features/Launcher/Service/AliasStore.swift \
                           Ministart/Features/Launcher/Service/VisibilityStore.swift \
                           Ministart/Features/Launcher/Service/BundleNameCache.swift \
                           Ministart/Platform/AppDisplayName.swift Ministart/Platform/BundleLocalization.swift \
                           Ministart/Platform/SystemLanguages.swift \
                           Ministart/Platform/Images/FileIconStamp.swift Ministart/Platform/Memo.swift \
                           Ministart/Platform/Signposts.swift Ministart/Platform/NotificationToken.swift \
                           Ministart/Platform/LocalizedResource.swift
run launcher-file-test     $L/LauncherFileFormat.swift \
                           Ministart/Features/Settings/Model/SettingsFileJSON.swift
run launcher-settings-file-test \
                           $L/LauncherFileFormat.swift $L/CommandID.swift $L/CommandCatalog.swift \
                           Ministart/Features/Launcher/Service/LauncherSettingsFile.swift \
                           Ministart/Features/Launcher/Service/AliasStore.swift \
                           Ministart/Features/Launcher/Service/VisibilityStore.swift \
                           Ministart/Features/Settings/SettingsTab.swift \
                           Ministart/Features/Settings/Model/*.swift \
                           Ministart/Features/HotKeys/Service/HotKeySettingsFile.swift \
                           Ministart/Features/HotKeys/Service/KeyShortcut.swift \
                           Ministart/Features/HotKeys/Model/HotKeyAction.swift \
                           Ministart/Features/HotKeys/Model/HotKeyBinding.swift \
                           Ministart/Features/HotKeys/Model/HotKeySpelling.swift \
                           Ministart/Features/HotKeys/Model/DoubleTapModifier.swift \
                           Ministart/Features/HotKeys/Model/ModifierKey.swift \
                           Ministart/Platform/ASCIIKeyboardLayout.swift \
                           Ministart/Features/Quicklinks/Model/Quicklink.swift \
                           Ministart/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Ministart/Features/Snippets/Model/Snippet.swift \
                           Ministart/Platform/LocalizedResource.swift
run apple-shortcut-test    Ministart/Features/AppleShortcuts/Model/*.swift
run calc-test              Ministart/Features/Calculator/Model/*.swift
run index calc-performance Ministart/Features/Calculator/Model/*.swift
run clipboard-test         Ministart/Features/Clipboard/Model/ClipboardStore.swift \
                           Ministart/Features/Clipboard/Model/RichTextFlattener.swift \
                           Ministart/Platform/Images/ImageDerivative.swift \
                           Ministart/Features/Clipboard/Model/ClipboardFilter.swift \
                           Ministart/Features/Clipboard/Model/ClipboardFileKind.swift \
                           Ministart/Features/Clipboard/Model/ColorValue.swift \
                           Ministart/Features/Clipboard/Model/ColorFormat.swift \
                           Ministart/Features/Clipboard/Model/ColorSpaces.swift
run clipboard-coordinator-test Ministart/Features/Clipboard/UI/ClipboardCoordinator.swift \
                           Ministart/Features/Clipboard/Model/*.swift \
                           Ministart/Platform/Images/ImageDerivative.swift \
                           Ministart/Palette/PaletteState.swift Ministart/Palette/PaletteMode.swift \
                           Ministart/Palette/HoverArming.swift \
                           Ministart/Features/Emoji/Model/EmojiCatalog.swift \
                           Ministart/Features/FileSearch/Model/FileSearchFilter.swift \
                           Ministart/Features/Quicklinks/Model/Quicklink.swift \
                           Ministart/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Ministart/Features/CustomCommands/Model/CustomCommand.swift
run clipboard-thumbnail-test Ministart/Features/Clipboard/Model/ClipboardStore.swift \
                           Ministart/Platform/Images/ImageDerivative.swift \
                           Ministart/Features/Clipboard/Model/ClipboardFilter.swift \
                           Ministart/Features/Clipboard/Model/ClipboardFileKind.swift \
                           Ministart/Features/Clipboard/Model/ColorValue.swift \
                           Ministart/Features/Clipboard/Model/ColorFormat.swift \
                           Ministart/Features/Clipboard/Model/ColorSpaces.swift \
                           Ministart/Platform/ProcessExit.swift \
                           Ministart/Platform/Images/ImageThumbnail.swift \
                           Ministart/Platform/Images/ThumbnailCache.swift
# `Q` is the URL detector a drag payload builds its link with, rather than a second one.
Q=Ministart/Features/Quicklinks/Model/QuicklinkDestination.swift
run paste-sequence-test    Ministart/Features/Clipboard/Model/*.swift Ministart/Platform/Images/ImageDerivative.swift $Q
run pasteboard-test        Ministart/Platform/PasteboardFiles.swift \
                           Ministart/Features/Clipboard/Model/RichTextFlattener.swift \
                           Ministart/Features/Clipboard/Model/ClipboardStore.swift \
                           Ministart/Platform/Images/ImageDerivative.swift \
                           Ministart/Features/Clipboard/Model/ClipboardFilter.swift \
                           Ministart/Features/Clipboard/Model/ClipboardFileKind.swift \
                           Ministart/Features/Clipboard/Model/ColorValue.swift \
                           Ministart/Features/Clipboard/Model/ColorFormat.swift \
                           Ministart/Features/Clipboard/Model/ColorSpaces.swift \
                           Ministart/Features/Clipboard/Service/ClipboardManager.swift \
                           Ministart/Features/Clipboard/Service/Paster.swift
run index clipboard-file-performance \
                           Ministart/Platform/PasteboardFiles.swift \
                           Ministart/Features/Clipboard/Model/ClipboardStore.swift \
                           Ministart/Platform/Images/ImageDerivative.swift \
                           Ministart/Features/Clipboard/Model/ClipboardFilter.swift \
                           Ministart/Features/Clipboard/Model/ClipboardFileKind.swift \
                           Ministart/Features/Clipboard/Model/ColorValue.swift \
                           Ministart/Features/Clipboard/Model/ColorFormat.swift \
                           Ministart/Features/Clipboard/Model/ColorSpaces.swift \
                           Ministart/Features/Clipboard/Service/ClipboardManager.swift
run index clipboard-thumbnail-performance \
                           Ministart/Platform/ProcessExit.swift \
                           Ministart/Platform/Images/ImageThumbnail.swift \
                           Ministart/Platform/Images/ImageDerivative.swift \
                           Ministart/Platform/Images/ThumbnailCache.swift
run emoji-test             Ministart/Features/Emoji/Model/EmojiCatalog.swift \
                           Ministart/Features/Emoji/Model/EmojiGridGeometry.swift \
                           Ministart/Features/Emoji/Model/EmojiData.generated.swift
run emoji-search-test      Ministart/Features/Emoji/Model/EmojiCatalog.swift \
                           Ministart/Features/Emoji/Model/EmojiData.generated.swift \
                           Ministart/Features/Emoji/Service/EmojiIndex.swift \
                           Ministart/Features/Emoji/Service/FrequentEmojiStore.swift \
                           Ministart/Features/Emoji/Service/PinnedEmojiStore.swift \
                           Ministart/Features/Launcher/Model/SearchRelevance.swift \
                           Ministart/Platform/AppPaths.swift Ministart/Platform/Memo.swift
run index emoji-search-performance \
                           Ministart/Features/Emoji/Model/EmojiCatalog.swift \
                           Ministart/Features/Emoji/Model/EmojiData.generated.swift \
                           Ministart/Features/Emoji/Service/EmojiIndex.swift \
                           Ministart/Features/Emoji/Service/FrequentEmojiStore.swift \
                           Ministart/Features/Launcher/Model/SearchRelevance.swift \
                           Ministart/Platform/AppPaths.swift Ministart/Platform/Memo.swift
run palette-selection-test Ministart/Features/PaletteRowIndex.swift \
                           Ministart/Features/Emoji/Model/EmojiGridGeometry.swift
run appearance-test        Ministart/Platform/Appearance.swift \
                           Ministart/DesignSystem/Theme.swift \
                           Ministart/DesignSystem/InterfaceMetrics.swift \
                           Ministart/Features/Settings/AppAppearance.swift
run language-test          Ministart/Features/Settings/AppLanguage.swift
run localized-resource-test Ministart/Platform/LocalizedResource.swift
run exclusive onboarding-test Ministart/Features/Onboarding/OnboardingCoordinator.swift \
                           Ministart/Windows/AppWindowController.swift \
                           Ministart/DesignSystem/Interaction/Motion.swift \
                           Ministart/Windows/WindowChrome.swift Ministart/Platform/ActivationPolicy.swift
run relaunch-test          Ministart/App/AppDelegate.swift Ministart/Platform/RelaunchRunner.swift
run interface-size-test    Ministart/Platform/Appearance.swift \
                           Ministart/DesignSystem/Theme.swift \
                           Ministart/DesignSystem/InterfaceMetrics.swift \
                           Ministart/Features/Settings/InterfaceSize.swift \
                           Ministart/Features/Extensions/Model/ExtensionFormMetrics.swift
run palette-placement-test Ministart/Platform/Appearance.swift \
                           Ministart/DesignSystem/Theme.swift \
                           Ministart/DesignSystem/InterfaceMetrics.swift \
                           Ministart/Features/Settings/InterfaceSize.swift \
                           Ministart/Palette/PalettePlacement.swift
run palette-menu-click-test Ministart/Platform/Appearance.swift \
                           Ministart/DesignSystem/Theme.swift \
                           Ministart/Platform/WindowLevel.swift \
                           Ministart/Platform/NotificationToken.swift \
                           Ministart/DesignSystem/Interaction/KeyboardFocus.swift \
                           Ministart/DesignSystem/Interaction/Motion.swift \
                           Ministart/DesignSystem/Interaction/AnimatedPanel.swift \
                           Ministart/Palette/PalettePanel.swift
run form-input-test        Ministart/Platform/Appearance.swift \
                           Ministart/DesignSystem/Theme.swift \
                           Ministart/DesignSystem/InterfaceMetrics.swift \
                           Ministart/DesignSystem/FormTextInput.swift \
                           Ministart/DesignSystem/FormTextArea.swift
run scroll-reveal-test     Ministart/DesignSystem/Scrolling/SelectionReveal.swift
run keyboard-focus-test    Ministart/DesignSystem/Interaction/KeyboardFocus.swift
run command-escape-tap-test Ministart/Palette/CommandEscapeTap.swift
run palette-escape-test    Ministart/Palette/PaletteMode.swift \
                           Ministart/Palette/PaletteEscapeAction.swift \
                           Ministart/Palette/CommandEscapeTap.swift \
                           Ministart/Features/Settings/EscapeKeyBehavior.swift \
                           Ministart/Features/Quicklinks/Model/Quicklink.swift \
                           Ministart/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Ministart/Features/CustomCommands/Model/CustomCommand.swift
run palette-navigation-test Ministart/Palette/PaletteState.swift \
                           Ministart/Palette/PaletteMode.swift \
                           Ministart/Palette/HoverArming.swift \
                           Ministart/Features/Emoji/Model/EmojiCatalog.swift \
                           Ministart/Features/Clipboard/Model/ClipboardStore.swift \
                           Ministart/Platform/Images/ImageDerivative.swift \
                           Ministart/Features/Clipboard/Model/ClipboardFilter.swift \
                           Ministart/Features/Clipboard/Model/ClipboardFileKind.swift \
                           Ministart/Features/FileSearch/Model/FileSearchFilter.swift \
                           Ministart/Features/Clipboard/Model/ColorValue.swift \
                           Ministart/Features/Clipboard/Model/ColorFormat.swift \
                           Ministart/Features/Clipboard/Model/ColorSpaces.swift \
                           Ministart/Features/Quicklinks/Model/Quicklink.swift \
                           Ministart/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Ministart/Features/CustomCommands/Model/CustomCommand.swift
run palette-filter-test    Ministart/Palette/PaletteMode.swift \
                           Ministart/Palette/PaletteFilterAction.swift \
                           Ministart/Features/Quicklinks/Model/Quicklink.swift \
                           Ministart/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Ministart/Features/CustomCommands/Model/CustomCommand.swift
run action-menu-search-test Ministart/Palette/ActionMenuSearchQuery.swift \
                            Ministart/Features/Launcher/Model/SearchRelevance.swift
run palette-shortcut-test  Ministart/Palette/PaletteShortcut.swift
run ascii-layout-test      Ministart/Platform/ASCIIKeyboardLayout.swift
run palette-tab-test       Ministart/Palette/PaletteMode.swift \
                           Ministart/Palette/PaletteTabAction.swift \
                           Ministart/Features/Quicklinks/Model/Quicklink.swift \
                           Ministart/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Ministart/Features/CustomCommands/Model/CustomCommand.swift
run fallback-test          Ministart/Features/Launcher/Model/Fallback.swift \
                           Ministart/Features/Launcher/Model/CommandID.swift \
                           Ministart/Features/HotKeys/Model/HotKeyAction.swift \
                           Ministart/Features/Quicklinks/Model/Quicklink.swift \
                           Ministart/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Ministart/Features/Snippets/Model/Snippet.swift \
                           Ministart/Platform/LocalizedResource.swift
run dictionary-test        Ministart/Features/Dictionary/Model/DictionaryEntry.swift \
                           Ministart/Features/Dictionary/Model/DictionaryMarkup.swift
run hotkey-test            Ministart/Features/HotKeys/Model/DoubleTapModifier.swift \
                           Ministart/Features/HotKeys/Model/ModifierKey.swift \
                           Ministart/Features/HotKeys/Model/ModifierKeyDetector.swift \
                           Ministart/Features/HotKeys/Model/DoubleTapDetector.swift \
                           Ministart/Features/HotKeys/Model/HotKeyBinding.swift \
                           Ministart/Features/HotKeys/Model/HotKeySpelling.swift \
                           Ministart/Platform/ASCIIKeyboardLayout.swift \
                           Ministart/Features/HotKeys/Service/KeyShortcut.swift \
                           Ministart/Features/HotKeys/Model/HotKeyAction.swift \
                           Ministart/Features/Launcher/Model/CommandID.swift \
                           Ministart/Features/Quicklinks/Model/Quicklink.swift \
                           Ministart/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Ministart/Features/Snippets/Model/Snippet.swift \
                           Ministart/Platform/LocalizedResource.swift
run callout-test          Ministart/Platform/Appearance.swift \
                           Ministart/DesignSystem/Theme.swift \
                           Ministart/DesignSystem/InterfaceMetrics.swift \
                           Ministart/Features/HotKeys/UI/CalloutPlacement.swift
run icon-cache-test        Ministart/Platform/Appearance.swift \
                           Ministart/Platform/Images/IconCache.swift
run entry-icon-test        Ministart/Platform/Appearance.swift \
                           Ministart/Platform/Images/IconCache.swift \
                           Ministart/Platform/Images/FileIconStamp.swift
run ext-icon-test          Ministart/Platform/Appearance.swift \
                           Ministart/Platform/AppDisplayName.swift \
                           Ministart/Platform/Images/IconCache.swift \
                           Ministart/Platform/Compression/Zlib.swift \
                           Ministart/DesignSystem/Theme.swift \
                           Ministart/DesignSystem/InterfaceMetrics.swift \
                           Ministart/Features/Extensions/Model/ExtensionBootConfig.swift \
                           Ministart/Features/Extensions/Model/ExtensionLaunchType.swift \
                           Ministart/Features/Extensions/Model/ExtensionManifest.swift \
                           Ministart/Features/Extensions/Model/ExtensionRefreshPolicy.swift \
                           Ministart/Features/Extensions/Model/ExtensionRefreshState.swift \
                           Ministart/Features/Extensions/Model/RenderNode.swift \
                           Ministart/Features/Extensions/Service/ExtensionCatalog.swift \
                           Ministart/Features/Extensions/Service/ExtensionFetcher.swift \
                           Ministart/Platform/ProcessExit.swift \
                           Ministart/Features/Extensions/Service/ExtensionNodeShims.swift \
                           Ministart/Features/Extensions/Service/ExtensionRuntime.swift \
                           Ministart/Features/Extensions/Service/ExtensionIconCache.swift \
                           Ministart/Features/Extensions/UI/ExtensionAnimatedImage.swift \
                           Ministart/Features/Extensions/UI/ExtensionImage.swift \
                           Ministart/Features/Clipboard/Model/ColorValue.swift \
                           Ministart/Features/Clipboard/Model/ColorSpaces.swift
run custom-command-test    Ministart/Platform/PseudoTerminal.swift \
                           Ministart/Platform/ProcessExit.swift \
                           Ministart/Features/CustomCommands/Model/CustomCommand.swift \
                           Ministart/Features/CustomCommands/UI/CustomCommandEditorSession.swift \
                           Ministart/Features/CustomCommands/Service/ShellCommandRunner.swift
run ansi-test              Ministart/DesignSystem/Theme.swift \
                           Ministart/Platform/Appearance.swift \
                           Ministart/Features/CustomCommands/UI/TerminalLogView.swift
run custom-command-list-test Ministart/Features/CustomCommands/Model/CustomCommand.swift \
                             Ministart/Features/CustomCommands/UI/CustomCommandListScreen.swift
run uninstall-coordinator-test Ministart/Features/Uninstall/Model/*.swift \
                           Ministart/Features/Uninstall/UI/UninstallCoordinator.swift
run uninstall-test         Ministart/Features/Uninstall/Model/UninstallTarget.swift \
                           Ministart/Features/Uninstall/Model/UninstallSearchRoot.swift \
                           Ministart/Features/Uninstall/Model/UninstallRules.swift \
                           Ministart/Features/Uninstall/Model/UninstallProtection.swift \
                           Ministart/Features/Uninstall/Model/UninstallPlan.swift
run quicklink-test         Ministart/Features/Quicklinks/Model/Quicklink.swift \
                           Ministart/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Ministart/Features/Quicklinks/Model/QuicklinkStore.swift \
                           Ministart/Features/Quicklinks/Model/QuicklinkArchive.swift \
                           Ministart/Features/Quicklinks/UI/QuicklinkEditorSession.swift
run quicklink-coordinator-test Ministart/Features/Quicklinks/Model/Quicklink.swift \
                           Ministart/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Ministart/Features/Quicklinks/Model/QuicklinkStore.swift \
                           Ministart/Features/Quicklinks/Model/QuicklinkArchive.swift \
                           Ministart/Features/Quicklinks/UI/QuicklinkCoordinator.swift \
                           Ministart/Features/Quicklinks/UI/QuicklinkEditorSession.swift \
                           Ministart/Features/Quicklinks/UI/QuicklinkArgumentsAccessory.swift \
                           Ministart/Features/Snippets/Model/Snippet.swift \
                           Ministart/Features/Snippets/Model/SnippetTemplateEngine.swift
run slow snippets-test     Ministart/Platform/NotificationToken.swift \
                           Ministart/Platform/HealthTicker.swift \
                           Ministart/Platform/AccessibilityText.swift \
                           Ministart/Features/Snippets/Model/*.swift \
                           Ministart/Features/Snippets/Service/*.swift \
                           Ministart/Features/Snippets/UI/SnippetEditorSession.swift \
                           Ministart/Features/TextInjection/Service/*.swift
run notes-test             Ministart/Platform/Signposts.swift \
                           $L/SearchRelevance.swift \
                           Ministart/Features/Notes/Model/*.swift \
                           Ministart/Features/Notes/Service/*.swift
run notes-editor-test      Ministart/Platform/Signposts.swift \
                           Ministart/Platform/Appearance.swift \
                           Ministart/DesignSystem/Theme.swift \
                           Ministart/DesignSystem/InterfaceMetrics.swift \
                           Ministart/Platform/NotificationToken.swift \
                           Ministart/Features/TextInjection/Service/InjectableTextView.swift \
                           Ministart/Features/Notes/Model/NoteDocument.swift \
                           Ministart/Features/Notes/Model/NoteTitle.swift \
                           Ministart/Features/Notes/Model/NoteMarkdown.swift \
                           Ministart/Features/Notes/Model/NoteMarkdownParser.swift \
                           Ministart/Features/Notes/Model/NoteInlineScanner.swift \
                           Ministart/Features/Notes/Model/NoteEditPlan.swift \
                           Ministart/Features/Notes/Model/NoteEditAction.swift \
                           Ministart/Features/Notes/Model/NoteFormatting.swift \
                           Ministart/Features/Notes/Model/NoteMarkdownEditing.swift \
                           Ministart/Features/Notes/Model/NoteRevealPolicy.swift \
                           Ministart/Features/Notes/UI/NoteMarkdownTypography.swift \
                           Ministart/Features/Notes/UI/NoteBlockDecoration.swift \
                           Ministart/Features/Notes/UI/NoteMarkdownStyler.swift \
                           Ministart/Features/Notes/UI/NoteMarkdownRenderer.swift \
                           Ministart/Features/Notes/UI/NoteCheckboxGeometry.swift \
                           Ministart/Features/Notes/UI/NoteBlockLayoutFragment.swift \
                           Ministart/Features/Notes/UI/NoteLayoutFragmentProvider.swift \
                           Ministart/Features/Notes/UI/NoteTextViewEditing.swift \
                           Ministart/Features/Notes/UI/NoteTextView.swift \
                           Ministart/Features/Notes/UI/NoteEditorView.swift
run -O index notes-editor-performance \
                           Ministart/Platform/Signposts.swift \
                           Ministart/Platform/Appearance.swift \
                           Ministart/DesignSystem/Theme.swift \
                           Ministart/DesignSystem/InterfaceMetrics.swift \
                           Ministart/Platform/NotificationToken.swift \
                           Ministart/Features/TextInjection/Service/InjectableTextView.swift \
                           Ministart/Features/Notes/Model/NoteDocument.swift \
                           Ministart/Features/Notes/Model/NoteTitle.swift \
                           Ministart/Features/Notes/Model/NoteMarkdown.swift \
                           Ministart/Features/Notes/Model/NoteMarkdownParser.swift \
                           Ministart/Features/Notes/Model/NoteInlineScanner.swift \
                           Ministart/Features/Notes/Model/NoteEditPlan.swift \
                           Ministart/Features/Notes/Model/NoteEditAction.swift \
                           Ministart/Features/Notes/Model/NoteFormatting.swift \
                           Ministart/Features/Notes/Model/NoteMarkdownEditing.swift \
                           Ministart/Features/Notes/Model/NoteRevealPolicy.swift \
                           Ministart/Features/Notes/UI/NoteMarkdownTypography.swift \
                           Ministart/Features/Notes/UI/NoteBlockDecoration.swift \
                           Ministart/Features/Notes/UI/NoteMarkdownStyler.swift \
                           Ministart/Features/Notes/UI/NoteMarkdownRenderer.swift \
                           Ministart/Features/Notes/UI/NoteCheckboxGeometry.swift \
                           Ministart/Features/Notes/UI/NoteBlockLayoutFragment.swift \
                           Ministart/Features/Notes/UI/NoteLayoutFragmentProvider.swift \
                           Ministart/Features/Notes/UI/NoteTextViewEditing.swift \
                           Ministart/Features/Notes/UI/NoteTextView.swift \
                           Ministart/Features/Notes/UI/NoteEditorView.swift
run settings-backup-test   Ministart/Features/Settings/AppSettingsKey.swift \
                           Ministart/Features/Backup/Model/SettingsBackupCoverage.swift
run settings-file-test     Ministart/Features/Settings/Model/*.swift \
                           Ministart/Features/Settings/Service/SettingsFileMonitor.swift \
                           Ministart/Features/Settings/Service/SettingsFileRepository.swift \
                           Ministart/Platform/AppPaths.swift
run backup-archive-test    Ministart/Platform/AppPaths.swift \
                           Ministart/Features/Backup/Model/BackupArchive.swift \
                           Ministart/Features/Backup/Model/BackupBundle.swift \
                           Ministart/Features/Backup/Model/BackupCategory.swift \
                           Ministart/Features/Backup/Model/BackupClipboardItem.swift \
                           Ministart/Features/Backup/Model/BackupManifest.swift \
                           Ministart/Features/Backup/Service/BackupStaging.swift
E=Ministart/Features/Extensions
run symbols-test           $E/Service/SymbolCatalog.swift
run ext-cleanup-test       $E/Service/ExtensionCleanup.swift \
                           $E/Service/ExtensionCatalog.swift \
                           Ministart/Platform/AppDisplayName.swift \
                           $E/Model/ExtensionManifest.swift \
                           $E/Model/ExtensionLaunchType.swift \
                           $E/Model/ExtensionRefreshPolicy.swift \
                           $E/Model/ExtensionRefreshState.swift
run ext-refresh-test       $E/Model/ExtensionManifest.swift \
                           Ministart/Platform/AppDisplayName.swift \
                           $E/Model/ExtensionLaunchType.swift \
                           $E/Model/ExtensionRefreshPolicy.swift \
                           $E/Model/ExtensionRefreshState.swift
run ext-metadata-test      $E/Model/ExtensionCommandMetadata.swift \
                           $E/Model/ExtensionMenuBarSnapshot.swift \
                           $E/Service/ExtensionCommandMetadataStore.swift
run ext-version-test       $E/Model/ExtensionListing.swift \
                           $E/Service/ExtensionVersionStore.swift
run ext-store-test         $E/Model/ExtensionGitHubSource.swift \
                           $E/Model/ExtensionListing.swift \
                           $E/Model/ExtensionPackageManager.swift \
                           $E/Model/ExtensionStoreResponse.swift
run ext-form-test          $E/Model/ExtensionFormMetrics.swift \
                           $E/Model/ExtensionFormField.swift \
                           $E/UI/ExtensionFormKey.swift \
                           $E/Model/ExtensionDateExpression.swift \
                           $E/UI/ExtensionListKey.swift \
                           Tests/ext-list-key-test.swift
run ext-image-size-test   $E/Model/ExtensionImageSize.swift
run ext-accessory-test     $E/Model/RenderNode.swift \
                           $E/Model/ExtensionPickerItem.swift \
                           $E/Model/ExtensionSearchAccessory.swift \
                           $E/Service/ExtensionStorage.swift
run slow ext-test          -parse-as-library \
                           Tests/ext-menu-bar-test.swift \
                           Tests/ext-fetch-test.swift \
                           $E/Model/ExtensionLaunchError.swift \
                           $E/Model/ExtensionMenuBarSnapshot.swift \
                           $E/Service/ExtensionStorage.swift \
                           $E/Service/ExtensionMenuBarManager.swift \
                           $E/Model/ExtensionCommandMetadata.swift \
                           $E/Service/ExtensionCommandMetadataStore.swift \
                           $E/UI/ExtensionMenuBarController.swift \
                           $E/UI/ExtensionMenuBarImage.swift \
                           Ministart/Platform/Appearance.swift \
                           Ministart/Platform/AppDisplayName.swift \
                           Ministart/Platform/Images/IconCache.swift \
                           Ministart/DesignSystem/Theme.swift \
                           Ministart/DesignSystem/InterfaceMetrics.swift \
                           $E/Model/ExtensionBootConfig.swift \
                           $E/Model/ExtensionDeepLink.swift \
                           $E/Model/ExtensionLaunchType.swift \
                           $E/Model/ExtensionFormField.swift \
                           $E/Model/ExtensionGridLayout.swift \
                           $E/Model/ExtensionSearchState.swift \
                           $E/Model/ExtensionManifest.swift \
                           $E/Model/ExtensionRefreshPolicy.swift \
                           $E/Model/ExtensionRefreshState.swift \
                           $E/Model/RenderNode.swift \
                           $E/Model/ExtensionPickerItem.swift \
                           $E/Model/ExtensionSearchAccessory.swift \
                           $E/Service/ExtensionCatalog.swift \
                           $E/Service/ExtensionFetcher.swift \
                           Ministart/Platform/ProcessExit.swift \
                           $E/Service/ExtensionIconCache.swift \
                           $E/Service/ExtensionNodeShims.swift \
                           $E/Service/ExtensionRuntime.swift \
                           $E/Service/ExtensionNameResolver.swift \
                           $E/Service/ExtensionWebSocketBridge.swift \
                           $E/UI/ExtensionAnimatedImage.swift \
                           $E/UI/ExtensionImage.swift \
                           $E/UI/ExtensionScreen.swift \
                           $L/SearchRelevance.swift \
                           Ministart/Platform/Compression/Zlib.swift \
                           Ministart/Features/Clipboard/Model/ColorValue.swift \
                           Ministart/Features/Clipboard/Model/ColorSpaces.swift
run settings-history-test  Ministart/Features/Settings/SettingsTab.swift \
                           Ministart/Features/Settings/SettingsHistory.swift \
                           Ministart/Features/Settings/SettingsAnchor.swift \
                           Ministart/Features/Settings/SettingsNavigationState.swift \
                           Ministart/Features/Settings/SettingsSearchCatalog.swift \
                           $L/SearchRelevance.swift \
                           Ministart/Platform/LocalizedResource.swift

if [ "$emit_db" -eq 1 ]; then
    printf ']\n' >> "$DB"
    [ -f .compile ] || echo '[]' > .compile
    node -e '
const fs = require("node:fs");
const [comp, db] = process.argv.slice(1);
const existing = JSON.parse(fs.readFileSync(comp, "utf8"));
const harnesses = JSON.parse(fs.readFileSync(db, "utf8"));
const kept = existing.filter((e) => !(e.files || []).some((f) => f.includes("/Tests/")));
fs.writeFileSync(comp, JSON.stringify([...kept, ...harnesses], null, 1));
console.log(harnesses.length + " harness entries indexed into .compile");
' .compile "$DB"
    exit 0
fi

if [ "$ran" -eq 0 ]; then
    echo "No harness named '$only'." >&2
    exit 2
fi

# `sort -s` is stable, so the slow harnesses lead and everything else keeps its declaration order.
JOBS="${MINISTART_TEST_JOBS:-4}"
export MINISTART_TEST_TIMEOUT="${MINISTART_TEST_TIMEOUT:-300}"
started=$SECONDS

# Numbers each result, and names what is still running whenever the output goes quiet.
report() {
    local finished=0 line asked running file
    while :; do
        asked=$SECONDS
        if IFS= read -r -t 15 line; then
            case "$line" in "dispatch "*) return "${line#dispatch }";; esac
            finished=$((finished + 1))
            printf '[%*d/%d] %s\n' "${#ran}" "$finished" "$ran" "$line"
            continue
        fi
        # Bash 3.2 returns the same status for a timeout and EOF; only EOF comes back at once.
        if [ $((SECONDS - asked)) -lt 10 ]; then return 1; fi
        running=""
        for file in "$BIN"/*.running; do
            [ -e "$file" ] && running="$running $(basename "$file" .running)"
        done
        printf '        \033[2mstill running after %ds:%s\033[0m\n' $((SECONDS - started)) "$running"
    done
}

dispatch() {
    [ -s "$1" ] || return 0
    sort -s -k1,1n "$1" | cut -d' ' -f2- | xargs -P "$2" -L1 "$SELF" --exec
}

# Without this the suite reports "all passed" whenever dispatch itself dies and no harness ran.
if ! {
    dispatch "$QUEUE" "$JOBS" && dispatch "$EXCLUSIVE_QUEUE" 1
    echo "dispatch $?"
} | report; then
    echo "harness dispatch failed; no result below can be trusted" >&2
    exit 1
fi
elapsed=$((SECONDS - started))

# A compiler diagnostic is far longer than PIPE_BUF, so the workers log it and it is replayed here.
while read -r _ name _; do
    if [ -f "$BIN/$name.failed" ]; then failed+=("$name"); fi
done < <(cat "$QUEUE" "$EXCLUSIVE_QUEUE")

if [ ${#failed[@]} -gt 0 ]; then
    for name in "${failed[@]}"; do
        printf '\n\033[31m--- %s ---\033[0m\n' "$name"
        cat "$BIN/$name.log"
    done
    printf '\n\033[31mFAILED\033[0m  %d of %d harness(es) failed in %ds: %s\n' \
        "${#failed[@]}" "$ran" "$elapsed" "${failed[*]}" >&2
    exit 1
fi
printf '\n\033[32mPASSED\033[0m  All %d harness(es) passed in %ds.\n' "$ran" "$elapsed"
