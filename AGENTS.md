This is a set of demos for the Dyad modeling framework.

Each demo must:
- Be a standalone project that can run independently
- Have an `assets/icon.svg` file that is a clip-art representation of what that
  demo is meant for
- Have an entry in the toplevel README.md file that links to the demo and
  provides a short description

Within each demo:
- Every component the user can see needs an icon and graphical metadata. Two
  kinds never appear as
  icons and are exempt:
  - test components
  - toplevel components
- Each library should have tests, they can be Julia-level tests or snapshot
  tests via the Dyad metadata (or both!).