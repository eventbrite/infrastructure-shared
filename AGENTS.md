# Agent instructions

## Scope

- Keep public module interfaces backward compatible.
- Keep modules in `_/` private and consume it only from modules in this repository.
- Do not add provider configuration, backends, or Spacelift resources. Data sources are allowed when required for caller-provisioned resources such as `datadog/api-key`.

## Terraform

- Use Terraform >= 1.5.0 and AWS provider >= 5.68.
- Sort `variable` blocks alphabetically by variable name and `output` blocks alphabetically by output name.
- Sort attributes alphabetically in every `map(object(...))`, `object(...)`, and nested object type in variable declarations.
- Sort top-level argument assignments in `resource`, `data`, and `module` blocks alphabetically as well; keep `count` and `for_each` first with a blank line after them, and keep other Terraform meta-arguments and nested blocks in their logical order. Keep `lifecycle` immediately before a final `depends_on`.
- Inline values used only once instead of introducing locals; keep locals for reused values or complex structures whose inlining would reduce readability.

## Documentation and releases

- Keep module READMEs focused on purpose, behavior, usage, and operational notes. Do not duplicate input or output reference tables in markdown; use `variables.tf` and `outputs.tf` as the interface documentation.
- Keep module READMEs reasonably self-contained and developer-oriented: explain required caller-owned resources, defaults, runtime prerequisites, and provide a complete usage example. Keep module-specific behavior guidance in the main Usage section.
- Format HCL examples in README files according to `terraform fmt` conventions.
- Keep Python runtime dependencies empty; manage Ruff and ty as uv development dependencies.
- Update the affected `CHANGELOG.md` files with user-visible changes.

## Validation

- Run `terraform fmt -check -recursive .`.
- Validate every changed module with `terraform init -backend=false` followed by `terraform validate`.
