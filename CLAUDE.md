# Pokyny pre Claude Code

## Ziadne git worktree

Pracuj VZDY priamo v tomto priecinku (`C:\Projekty\Private\JurhanService\Deploy`) na jeho
aktualnej branchi. Nepouzivaj `EnterWorktree` ani `git worktree add`, nevytvaraj nic
v `.claude/worktrees/`.

Ak sa session uz spusti vo worktree, upozorni na to a zmeny presun sem (a worktree odregistruj).

Dovod: publish/install skripty si koren zdrojov odvodzuju z `$PSScriptRoot\..`. Vo worktree
to je `Deploy\.claude\worktrees` namiesto `C:\Projekty\Private\JurhanService`, takze
`dotnet publish` zlyha na "csproj nenajdeny".
