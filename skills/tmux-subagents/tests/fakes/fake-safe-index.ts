import { buildClaudeLaunchArgs } from "./claude-command.ts";

declare const cmdParts: string[];
declare function shellEscape(value: string): string;

const claudeArgs = buildClaudeLaunchArgs({ task: "test" });
cmdParts.push(...claudeArgs.map(shellEscape));
