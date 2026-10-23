import {
  ArrowRight,
  Cpu,
  FileCode2,
  FileText,
  Ghost,
  Image as ImageIcon,
  LayoutGrid,
  Link2,
  Paperclip,
  Search,
} from "lucide-react";
import type { ComponentType, ReactNode } from "react";
import type { FeaturePreview } from "../data/features";
import { cn } from "../lib/cn";
import { GitHubLogo } from "./ui/icon";

// Small illustrations of each feature, drawn in HTML so they follow the theme.
// Every label is a real string from the app or its docs.

function Caret() {
  return (
    <span
      aria-hidden="true"
      className="demo-caret ml-px inline-block h-[1.1em] w-px translate-y-[0.15em] bg-violet-bright"
    />
  );
}

function IconTile({
  icon: Icon,
  tint,
}: {
  icon: ComponentType<{ size?: number }>;
  tint: string;
}) {
  return (
    <span
      className="flex size-6 shrink-0 items-center justify-center rounded-md text-white"
      style={{ background: tint }}
    >
      <Icon size={13} />
    </span>
  );
}

function LauncherPreview() {
  const rows = [
    {
      name: "Ghostty",
      kind: "Application",
      icon: Ghost,
      tint: "linear-gradient(160deg, #3d5afe, #0d1b6e)",
    },
    {
      name: "GitHub Desktop",
      kind: "Application",
      icon: GitHubLogo,
      tint: "linear-gradient(160deg, #a875ff, #5b12bd)",
    },
    {
      name: "Search GitHub",
      kind: "Quicklink",
      icon: Link2,
      tint: "linear-gradient(160deg, #47bfff, #1769aa)",
    },
  ];
  return (
    <div className="flex h-full flex-col">
      <p className="flex items-center gap-2 px-2 pb-2 text-body text-fg">
        <Search size={15} className="text-fg-muted" aria-hidden="true" />
        <span>
          gh
          <Caret />
        </span>
      </p>
      <ul className="flex flex-col gap-0.5">
        {rows.map((row, i) => (
          <li
            key={row.name}
            className={cn(
              "flex items-center gap-2.5 rounded-lg px-2 py-1.5",
              i === 0 && "bg-tint/8",
            )}
          >
            <IconTile icon={row.icon} tint={row.tint} />
            <span className="text-small text-fg">{row.name}</span>
            <span className="ml-auto text-caption text-fg-subtle">
              {row.kind}
            </span>
          </li>
        ))}
      </ul>
    </div>
  );
}

function CalculatorPreview() {
  return (
    <div className="flex h-full flex-col justify-center gap-1 px-1">
      <p className="text-small text-fg-muted">560 km to mi</p>
      <p className="text-subheading font-semibold tracking-tight text-fg">
        347.9678677 mi
      </p>
      <p className="mt-2 inline-flex w-fit rounded-full bg-violet/15 px-2.5 py-0.5 text-caption font-medium text-violet-bright">
        Copy Answer ↵
      </p>
    </div>
  );
}

function ClipboardPreview() {
  return (
    <ul className="flex h-full flex-col justify-center gap-1.5">
      <li className="flex items-center gap-2.5 rounded-lg bg-tint/8 px-2 py-1.5">
        <IconTile icon={FileText} tint="rgb(120 120 128 / 0.6)" />
        <span className="truncate font-mono text-caption text-fg">
          brew install --cask tinycast
        </span>
      </li>
      <li className="flex items-center gap-2.5 rounded-lg px-2 py-1.5">
        <span className="size-6 shrink-0 rounded-md bg-violet" />
        <span className="font-mono text-caption text-fg">#863BFF</span>
      </li>
      <li className="flex items-center gap-2.5 rounded-lg px-2 py-1.5">
        <IconTile
          icon={ImageIcon}
          tint="linear-gradient(135deg, #863bff, #47bfff)"
        />
        <span className="text-caption text-fg">Image · 2148×1302</span>
      </li>
    </ul>
  );
}

function WindowsPreview() {
  const layouts: { name: string; slot: string }[] = [
    { name: "Left Half", slot: "col-start-1 col-end-4" },
    { name: "Center Third", slot: "col-start-3 col-end-5" },
    { name: "First Two Thirds", slot: "col-start-1 col-end-5" },
  ];
  return (
    <ul className="grid h-full grid-cols-3 items-center gap-2 sm:gap-3">
      {layouts.map((layout) => (
        <li key={layout.name} className="flex flex-col gap-2">
          {/* A six-column screen, so halves (3) and thirds (2) both land on grid lines. */}
          <span className="grid aspect-16/10 grid-cols-6 gap-1 rounded-lg bg-tint/8 p-1.5">
            <span
              className={cn(
                "rounded-md bg-violet/70 ring-1 ring-violet-bright",
                layout.slot,
              )}
            />
          </span>
          <span className="text-center text-caption text-fg-muted">
            {layout.name}
          </span>
        </li>
      ))}
    </ul>
  );
}

function ExtensionsPreview() {
  const stages = [
    { label: "Extension code", icon: FileCode2 },
    { label: "JavaScriptCore", icon: Cpu },
    { label: "SwiftUI", icon: LayoutGrid },
  ];
  return (
    <ol className="flex h-full items-center justify-center gap-1.5 sm:gap-3">
      {stages.map((stage, i) => (
        <li key={stage.label} className="flex items-center gap-1.5 sm:gap-3">
          {i > 0 && (
            <ArrowRight
              size={14}
              className="shrink-0 text-fg-subtle"
              aria-hidden="true"
            />
          )}
          <span
            className={cn(
              "flex flex-col items-center gap-2 rounded-xl px-2 py-3 sm:px-4",
              i === stages.length - 1 ? "bg-violet/15" : "bg-tint/8",
            )}
          >
            <stage.icon
              size={18}
              aria-hidden="true"
              className={
                i === stages.length - 1 ? "text-violet-bright" : "text-fg-muted"
              }
            />
            <span className="text-center text-caption text-fg">
              {stage.label}
            </span>
          </span>
        </li>
      ))}
    </ol>
  );
}

function SnippetsPreview() {
  return (
    <div className="flex h-full items-center justify-center gap-3">
      <span className="rounded-lg bg-tint/8 px-3 py-2 font-mono text-small text-fg">
        !notes
        <Caret />
      </span>
      <ArrowRight
        size={14}
        className="shrink-0 text-fg-subtle"
        aria-hidden="true"
      />
      <span className="flex min-w-0 flex-col gap-1 rounded-lg bg-tint/8 px-3 py-2">
        <span className="truncate text-small font-semibold text-fg">
          Sunday, 13 September
        </span>
        <span className="truncate text-caption text-fg-muted">
          Attendees: <Caret />
        </span>
      </span>
    </div>
  );
}

const previews: Record<FeaturePreview, () => ReactNode> = {
  launcher: LauncherPreview,
  extensions: ExtensionsPreview,
  clipboard: ClipboardPreview,
  calculator: CalculatorPreview,
  windows: WindowsPreview,
  snippets: SnippetsPreview,
};

export function FeaturePreviewArt({ preview }: { preview: FeaturePreview }) {
  const Preview = previews[preview];
  return <Preview />;
}
