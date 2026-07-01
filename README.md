# Utility Scripts

A collection of shell scripts for repo management and codebase navigation.

## Scripts

- [`rfind.sh`](#rfindsh) — smart relevance-ranked search across a repo
- [`check_git_status.sh`](#check_git_statussh) — scans for dirty / unpushed / remote-less git repos

---

## `rfind.sh`

Intelligent search tool that scans a directory and ranks files/folders by relevance, combining path-based scoring with in-file content matching. Built for fast exploratory navigation of unknown or large repos rather than exact text search.

**Highlights**
- Hybrid scoring: filename, directory, full path, and content matches, plus a multi-keyword overlap bonus and a depth penalty for deeply nested results
- Content search inside text files only, with diminishing-returns frequency scoring
- Color-coded, icon-tagged terminal output
- Auto-filters noise: `node_modules`, `venv`, `__pycache__`, `dist`/`build`/`target`, hidden files, and itself

**Usage**
```bash
./rfind.sh                          # interactive mode (prompts for dir/keywords/depth/results)
./rfind.sh keyword1 keyword2        # command-line mode
./rfind.sh radio rf astronomy
```

**Example**
```
#1 [Score: 192]
  🎨 rjafari44.github.io/projects/radio_astronomy/small-rt-21cm.html
     └─ Path match: 102 | Content match: 90
```

---

## `check_git_status.sh`

Scans one or more directories for git repos and reports which ones have uncommitted changes, unpushed commits, or no remote configured.

**Usage**
```bash
./check_git_status.sh                 # scans $HOME by default
./check_git_status.sh ~/projects ~/dev
./check_git_status.sh -d 3 ~/projects # limit search depth (default: unlimited)
```

**Output**
Three sections: repos with uncommitted changes, repos with unpushed commits (branch + commit count ahead of upstream), and repos with no remote configured. Automatically skips `node_modules` and `.cache`.