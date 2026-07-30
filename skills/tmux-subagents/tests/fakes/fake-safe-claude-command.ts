export const CLAUDE_LAUNCH_POLICY = "manual-permissions-v1" as const;

interface LaunchOptions {
  model?: string;
  pluginDir?: string;
  resumeSessionId?: string;
  systemPrompt?: string;
  task: string;
}

export function buildClaudeLaunchArgs(options: LaunchOptions): string[] {
  const args = ["--permission-mode", "manual"];
  if (options.pluginDir) args.push(`--plugin-dir=${options.pluginDir}`);
  if (options.model) args.push(`--model=${options.model}`);
  if (options.systemPrompt) args.push(`--append-system-prompt=${options.systemPrompt}`);
  if (options.resumeSessionId) args.push(`--resume=${options.resumeSessionId}`);
  return [...args, "--", options.task];
}
