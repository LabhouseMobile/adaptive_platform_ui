# Release Process

Releases are cut from `main` by two GitHub Actions workflows. Nobody edits the
version or pushes tags by hand.

## While developing

Add every user-facing change to the `## [Unreleased]` section at the top of
`CHANGELOG.md`, in the usual format:

```markdown
## [Unreleased]
* **NEW**: Description of new features
* **FIX**: Description of bug fixes
* **IMPROVEMENT**: Description of improvements
```

## Cutting a release

1. Run the **Create new Release** workflow (`create-new-release.yml`) from the
   Actions tab, or:

   ```bash
   gh workflow run create-new-release.yml -f version=1.0.2
   ```

   The version is bare semver (`1.0.2`, `1.0.1-lh6`); a leading `v` is
   accepted and dropped. The workflow:
   - branches `release/v<version>` off `main`
   - runs `scripts/prepare_release.py`, which moves the Unreleased notes into a
     new `## [<version>]` section and sets `version:` in `pubspec.yaml`
   - commits `chore: release <version>` and opens a PR into `main` with the
     `Release` label and a compare link against the latest tag

   It fails if the Unreleased section is empty or the version already has a
   section.

2. Review and merge the PR.

3. On merge, **Create release from merged Release PR**
   (`release-on-merged-pr.yml`) tags the merge commit `v<version>` and creates
   the GitHub release, using that version's CHANGELOG section as the notes
   (falling back to GitHub's generated notes if the section is empty).

To preview the changelog change locally:

```bash
python3 scripts/prepare_release.py 1.0.2 --dry-run
```

## Versioning

Follow [Semantic Versioning](https://semver.org/). Tags always carry a `v`
prefix (`v1.0.2`); `pubspec.yaml` and the CHANGELOG headers do not (`1.0.2`).

## Fixing a bad release

Delete the release and its tag, then cut a new patch version:

```bash
gh release delete v1.0.2 --cleanup-tag
```
