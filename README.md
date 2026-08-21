# infrastructure-shared

Reusable Terraform modules for Eventbrite infrastructure.

## Contributing

1. Change only the affected module and its private dependencies.
2. Add release notes to the affected public module's next top-level semantic-version heading.
3. Run `terraform fmt -check -recursive .`.
4. In every changed module directory, run `terraform init -backend=false -input=false` followed by `terraform validate`.

Pull requests run formatting, validation, and release-metadata checks for every module. The release check reports the exact changelog update needed when source changes lack a new version.

## Releasing

1. Add a new top-level semantic-version heading to each affected public module's `CHANGELOG.md`.
2. Open and merge the pull request after CI passes.
3. The push to `main` runs the release workflow, which creates annotated tags and GitHub Releases in the form `<module>-<version>`.

Releases are published automatically after a merge to `main`; there is no manual release step.
