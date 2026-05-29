This is a set of demos for the Dyad modeling framework.

Each demo must:
- Be a standalone project that can run independently
- Have an `assets/icon.svg` file that is a clip-art representation of what that demo is meant for
- Have an entry in the toplevel README.md file that links to the demo and provides a short description

Within each demo:
- Every component that can be seen by the user must have an associated icon and graphical metadata.  Test components and toplevel components cannot be seen as icons by the user, so are exempt, but anything else must have the graphics hooked up.
- Each library should have tests, they can be Julia-level tests or snapshot tests via the Dyad metadata (or both!).