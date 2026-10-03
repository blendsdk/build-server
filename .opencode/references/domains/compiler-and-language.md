# Compiler and language ambiguity lens

Use this lens for programming languages, compilers, interpreters, query languages, schemas, protocol decoders, and systems with formal transformation semantics.

## Semantic closure checklist

- Source encoding, lexical rules, whitespace/comments, reserved words, and error recovery
- Complete grammar, precedence, associativity, ambiguity resolution, and parse-tree shape
- Namespaces, scopes, shadowing, imports, visibility, forward references, and cycles
- Type formation, equivalence, subtyping/coercion, inference, polymorphism, constraints, and error types
- Compile-time versus runtime behavior and phase ordering
- Constant evaluation, effects, evaluation order, overflow, undefined behavior, and determinism
- Ownership/lifetime/resource semantics where applicable
- IR invariants at every level and preservation between lowering passes
- Optimization preconditions and semantic-equivalence obligations
- Linking, modules, ABI, serialization, and version compatibility
- Diagnostics: location, recovery, cascades, stability, and machine-readable forms
- Incremental/parallel compilation invalidation and cache correctness
- Tooling contracts: formatter, language server, debugger, package manager, and build system
- Conformance, golden, differential, property, fuzz, and invalid-program tests

## Required counterexamples

For each semantic rule, seek minimal examples at boundaries: empty forms, recursive/cyclic forms, shadowing, ambiguous parses, conflicting constraints, order-sensitive effects, overflow, invalid encodings, partial programs, and cross-module interactions. A prose rule is incomplete until examples distinguish it from plausible alternatives.

## Gate

The semantics gate fails when two conforming implementations could produce observably different results from the same valid program/input, or when invalid input lacks a defined rejection/recovery class, unless that freedom is explicitly part of the language contract.
