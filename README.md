# Oxell

A Haskell-like language compiled to Rust (hence the name, derived from 'Oxidized Haskell').
See Rust runtime [here](https://github.com/ianmelendez95/oxell-runtime).

One *tentative* goal is to leverage the runtime and ecosystem of Rust, 
allowing the user to directly tap into the Rust ecosystem in their Oxell 
programs in a way that is much easier than what is available in Haskell.

In other words, this project hopes to leverage a dedicated Rust backend 
(e.g. without intending to support other backends) to enable features that 
would be difficult to support with a backend-agnostic implementation of Haskell. 

Really though, this is very much a prototypical project, and just getting a working 
language at all is the main goal.

## Roadmap

- [x] Integer values (literally the program "5" should compile)
- [x] Integer addition (e.g. "1 + 2")
- [x] Integer arithmetic (addition, subtraction, multiplication, division) (e.g. "1 + 2 / 3 * 4 - 5")
- [ ] Simple let expressions (e.g. "let x = 5 in x + 2")