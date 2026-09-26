# Synthetic PTY redraw fixtures

`usage-pty-differential-redraw.ansi` preserves the diff-frame layout from @fanwenlin's #3822 fixture. Unrelated startup output is removed; workspace and tool names are synthetic. Quotas and reset labels are fixed test data. The crucial redraw writes `us`, jumps past the previous frame's `e` in `does`, then writes `d`: stripping CSI sequences leaves `51%usd` instead of `51% used`.

`status-pty-differential-redraw.ansi` paints an old synthetic identity, then replaces it with `fixture@example.com`, `Example Org`, and `Claude Max Account`, using cursor jumps for spaces and erase-line for stale suffixes. No real CLI or account is used.
