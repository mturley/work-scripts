# milestones

Show upcoming RHOAI release milestones from Product Pages. Runs the `/milestones` Claude Code skill with the default model.

## Prerequisites

- [Claude Code](https://claude.ai/code) installed and on PATH
- The `/milestones` skill installed in `~/.claude/skills/`

## Usage

```bash
milestones                     # Major releases, next 3 months
milestones 6 months            # Major releases, next 6 months
milestones this year            # Major releases through end of year
milestones 3.5                 # All 3.5 milestones (EA1, EA2, GA)
milestones through 3.6         # Major milestones through 3.6 GA
milestones all                 # All releases (including patches), next 3 months
milestones all 6 months        # All releases, next 6 months
milestones all through 3.6     # All releases through 3.6 GA
milestones help                # Show help
```

All arguments are forwarded to the `/milestones` skill.
