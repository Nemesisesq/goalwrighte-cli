# Goalwrighte CLI

`goalwrighte` is the command a pipeline runs to start a Run on Goalwrighte Cloud and learn its
Verification. It starts a Run of a Site's stored Goals with an API token, waits for the
Results, prints each Goal's status and the Run page's address, and exits.

It exits 0 only when every Criterion of every Goal in the Run is verified passed. A Result is
never a pass by itself: a Run whose Results are all Completed unverified exits 5, and the job
stays red until a Member records Verification on the Run page. No flag makes it exit 0 without
Verification.

This repository holds the release binaries (linux and darwin, amd64 and arm64) with their
checksums, and a thin wrapper for GitHub, GitLab and RWX. Each wrapper only installs the
binary and runs it.

## Exit codes

| Exit | Meaning |
| --- | --- |
| 0 | Every Criterion verified passed |
| 1 | A Result other than Completed unverified, or a Criterion verified failed |
| 2 | Refused or misconfigured, including an empty API token |
| 3 | Platform failure or wait timeout |
| 4 | `quota_exhausted`: the Workspace's Plan has no Runs left this month |
| 5 | Completed unverified, awaiting Verification |

## Before you start

1. The Site is proven. A Run starts only on a Site whose Origin proof holds; on any other
   origin the start is refused and the job exits 2.
2. The Goals are stored on the Site. The CLI starts them by id. `GET /v1/sites` lists Site
   ids and `GET /v1/sites/{site}/goals` lists Goal ids.
3. An Owner creates an API token on the Workspace page. Store it where your pipeline keeps
   secrets, under the name `GOALWRIGHTE_API_TOKEN`. Read "A leaked API token" below first.

Every example pins a release tag such as `v1.2.3`. There is no "latest": choose a tag from
this repository's releases.

## The red job and the re-run

The job is red until a Member verifies. That suits a gate before a release or a nightly
pipeline. It is a poor required check on every push.

1. The job starts a Run, the Results arrive, and the job exits 5. Its output has the Run
   page's address.
2. A Member opens the Run page and records Verification for each Criterion.
3. The Member re-runs the job. It finds the same Run, starts nothing, uses no quota, and
   exits 0 when every Criterion is verified passed or 1 when one is verified failed.

The second invocation finds the Run because the CLI sends an `Idempotency-Key` built from the
Site, the commit, the Goals, `--start-url` and `--timeout`. A Run that ended `failed` or `canceled` does not hold its key,
so a re-run after a platform failure starts a new Run. `--new-run` starts another Run on a
commit that already has one.

To wait in the job instead of re-running it, pass `--wait-verification 30m`. The job then
keeps polling for that long and exits 5 only when the time runs out.

## GitHub

Pin the action by commit SHA, not by tag: a tag can be moved, a commit cannot. The `version`
input names the CLI release the action installs and is checked against that release's
checksums.

After a deploy:

```yaml
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - run: ./deploy.sh

  goalwrighte:
    needs: deploy
    runs-on: ubuntu-latest
    steps:
      - uses: Nemesisesq/goalwrighte-cli@<commit SHA of the v1.2.3 tag> # v1.2.3
        with:
          api-token: ${{ secrets.GOALWRIGHTE_API_TOKEN }}
          version: v1.2.3
          site: <Site id>
          goals: |
            <Goal id>
            <Goal id>
```

Every night:

```yaml
on:
  schedule:
    - cron: "17 6 * * *"

jobs:
  goalwrighte:
    runs-on: ubuntu-latest
    steps:
      - uses: Nemesisesq/goalwrighte-cli@<commit SHA of the v1.2.3 tag> # v1.2.3
        with:
          api-token: ${{ secrets.GOALWRIGHTE_API_TOKEN }}
          version: v1.2.3
          site: <Site id>
          goals: <Goal id> <Goal id>
          # The commit is often the same as last night's, so the first attempt starts a new
          # Run. A re-run of the job after Verification finds that Run.
          new-run: ${{ github.run_attempt == 1 }}
```

The action's other inputs are `start-url`, `timeout`, `wait`, `wait-verification` and
`base-url`. The CLI writes each Goal's status and the Run page link to the job summary.

A pull request from a fork gets no repository secrets, so the API token is empty and the job
exits 2. Start Runs from pushes to your own branches and from schedules.

To tolerate exit 5, run the CLI from a shell step instead of the action:

```yaml
      - env:
          GOALWRIGHTE_API_TOKEN: ${{ secrets.GOALWRIGHTE_API_TOKEN }}
          GOALWRIGHTE_VERSION: v1.2.3
        run: |
          curl -fsSL "https://raw.githubusercontent.com/Nemesisesq/goalwrighte-cli/$GOALWRIGHTE_VERSION/install.sh" | sh
          "$HOME/.local/bin/goalwrighte" run --site <Site id> --goal <Goal id> \
            --commit "$GITHUB_SHA" --ref "$GITHUB_REF" || [ $? -eq 5 ]
```

A job that tolerates exit 5 is green before any Member has verified. It says the Results
arrived, not that a Goal passed.

## GitLab

`gitlab.yml` holds a hidden job, `.goalwrighte-run`. Include it at a release tag and extend
it. The API token comes from a masked and protected CI/CD variable named
`GOALWRIGHTE_API_TOKEN`; a protected variable reaches protected branches only, so a job on
any other branch has no token and exits 2.

```yaml
include:
  - remote: https://raw.githubusercontent.com/Nemesisesq/goalwrighte-cli/v1.2.3/gitlab.yml

stages: [deploy, verify]

deploy:
  stage: deploy
  script: ./deploy.sh
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH

goalwrighte:
  extends: .goalwrighte-run
  stage: verify
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
  variables:
    GOALWRIGHTE_VERSION: v1.2.3
    GOALWRIGHTE_SITE: <Site id>
    GOALWRIGHTE_GOALS: <Goal id> <Goal id>
```

Optional variables: `GOALWRIGHTE_START_URL`, `GOALWRIGHTE_TIMEOUT`, `GOALWRIGHTE_WAIT`,
`GOALWRIGHTE_WAIT_VERIFICATION`, `GOALWRIGHTE_NEW_RUN` (`"true"`) and `GOALWRIGHTE_BASE_URL`.

A scheduled pipeline on a commit that already has a Run finds that Run. Setting
`GOALWRIGHTE_NEW_RUN: "true"` on the schedule starts a new one each night, and a retried job
then starts another, so on a schedule set `GOALWRIGHTE_WAIT_VERIFICATION` and verify while the
job waits.

To tolerate exit 5:

```yaml
goalwrighte:
  extends: .goalwrighte-run
  allow_failure:
    exit_codes: 5
```

## RWX

Copy `rwx.yml` into `.rwx/` and fill in the release tag, the Site id and the Goal ids. Its
`base` must have `curl` and `sha256sum` or `shasum`. The task sets `cache: false`: a cache hit would report an earlier exit code without starting a
Run. Keep the API token in a locked vault that only your repository's main branch may read.

```yaml
on:
  github:
    push:
      if: ${{ event.git.branch == 'main' }}
      init:
        commit-sha: ${{ event.git.sha }}
        ref: ${{ event.git.ref }}

base:
  image: ubuntu:26.04
  config: rwx/base 1.2.1

tasks:
  - key: goalwrighte-run
    cache: false
    env:
      GOALWRIGHTE_API_TOKEN: ${{ vaults.goalwrighte.secrets.GOALWRIGHTE_API_TOKEN }}
      GOALWRIGHTE_VERSION: v1.2.3
      COMMIT: ${{ init.commit-sha }}
      REF: ${{ init.ref }}
    run: |
      curl -fsSL -o install.sh "https://raw.githubusercontent.com/Nemesisesq/goalwrighte-cli/$GOALWRIGHTE_VERSION/install.sh"
      GOALWRIGHTE_BIN_DIR="$PWD/bin" sh install.sh
      exec ./bin/goalwrighte run --site <Site id> --goal <Goal id> --commit "$COMMIT" --ref "$REF"
```

RWX sets no commit or ref for a task that does not clone the repository, so the trigger hands
both to the task. `exec` lets the signal of a canceled run reach the CLI, which cancels the
Run. To tolerate exit 5, drop `exec` and end the last line with `|| [ $? -eq 5 ]`.

## Any other CI

`install.sh` is POSIX sh. It needs `curl` and either `sha256sum` or `shasum`, downloads the
binary for the machine's OS and architecture, and installs nothing unless its SHA-256 is the
one in the release's `checksums.txt`.

```sh
export GOALWRIGHTE_VERSION=v1.2.3
curl -fsSL "https://raw.githubusercontent.com/Nemesisesq/goalwrighte-cli/$GOALWRIGHTE_VERSION/install.sh" | sh

# GOALWRIGHTE_API_TOKEN comes from your pipeline's secret store.
"$HOME/.local/bin/goalwrighte" run --site <Site id> --goal <Goal id> --goal <Goal id> \
  --commit "$(git rev-parse HEAD)" --pipeline-url "<this pipeline's https URL>"
```

`GOALWRIGHTE_BIN_DIR` changes where the binary goes. To tolerate exit 5, end the last command
with `|| [ $? -eq 5 ]`.

```
goalwrighte run --site <id> --goal <id> [--goal <id> ...]
    [--start-url <URL>] [--timeout <seconds>] [--wait <duration>]
    [--wait-verification <duration>] [--new-run] [--base-url <URL>]
    [--commit <sha>] [--ref <ref>] [--pipeline-url <URL>]
goalwrighte version
```

The commit, ref and pipeline URL are shown on the Run page, so a Member can see what they are
verifying.

## A leaked API token

An API token is not limited to starting Runs. It belongs to the Workspace, has no expiry and
works until an Owner revokes it. Whoever holds it acts as a Member of the Workspace through
the API and the MCP server: they can read every Site's Goals and Runs, start and cancel Runs,
which uses the Plan's quota, and write Goals. It cannot record Verification.

- Keep it in your pipeline's secret store and nowhere else: a repository secret on GitHub, a
  masked and protected variable on GitLab, a locked vault on RWX.
- Do not give it to jobs that run code from outside your repository, such as pull requests
  from forks.
- Create one API token per pipeline, so revoking one stops one pipeline.
- If it leaks, an Owner revokes it on the Workspace page and creates another.

## Quota

- Each Run the CLI starts counts against the Plan's monthly Run quota. A nightly pipeline
  starts about 30 Runs a month.
- A re-run that finds its Run starts nothing and uses no quota. `--new-run` always starts a
  Run.
- When the quota is used up the CLI exits 4. It exits 4 as well when a Run ends with the
  failure reason `quota_exhausted`.
- `--timeout` cannot exceed the Plan's maximum; a larger value is refused and the job exits 2.
