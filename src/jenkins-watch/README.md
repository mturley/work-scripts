# jenkins-watch

Poll a Jenkins job or build every 10 seconds and show a macOS alert when its build completes. For a job URL, the script watches the latest build; for a build URL, it watches that specific build.

## Requirements

- macOS, for the `alert` command
- `curl`, `jq`, and `alert` available on `PATH`
- `JENKINS_URL`, `JENKINS_USER`, and `JENKINS_API_TOKEN` in the environment, or in a file passed with `--env`. The script exits with an error if any are missing or empty.
- For stage and running-step details, the Jenkins **Pipeline: REST API** plugin must be installed and the account must be able to access its endpoints. Without it, the script continues to monitor build status only.
- The `--env` file is sourced as shell code; only pass a file you trust. Its assignments are exported while the script runs.

Credential values are not printed or passed on curl's command line.

## Usage

```bash
jenkins-watch [--env <file>] <job-or-build-url>
```

Examples:

```bash
jenkins-watch https://jenkins.example.com/job/my-job/
jenkins-watch --env ~/secrets/jenkins.env https://jenkins.example.com/job/my-job/
jenkins-watch https://jenkins.example.com/job/my-job/42/ --env ~/secrets/jenkins.env
```

The command logs each request and, after a successful response, the build number and current status (`building` or `complete` with its result), each with a timestamp. Poll cycles are separated by a blank line. Statuses have colored symbols when output is a terminal (green ✓ success, cyan ● in progress, red ✗ failure, yellow ! warning/paused, blue ○ queued); symbols remain when color is unavailable, and `NO_COLOR` disables ANSI colors. When Pipeline REST API data is available, it logs every stage and its status individually. It expands step details only for an `IN_PROGRESS` stage; consecutive successful steps within that stage are collapsed into a count (for example, `[✓ 3 steps succeeded]`). These are Jenkins Pipeline flow nodes (for example, `Shell Script`), not individual lines of shell output. It polls indefinitely, retrying transient request or response errors every 10 seconds. When Jenkins reports that the build is no longer running, it calls `alert` with the build number and result.
