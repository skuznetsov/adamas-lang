#!/usr/bin/env python3
"""Compare original Crystal and Adamas LLVM function inventories.

The two compilers deliberately use different symbol spellings.  This tool does
not try to compare the spelling as an identity: original Crystal names are
parsed into a small semantic record and Adamas symbols are generated from that
record with the backend's forward mangler.  The reverse decoder is only a
display aid because Adamas' token alphabet is not prefix-free (for example,
``$LTuple`` can be ``$L`` + ``Tuple`` or ``$LT`` + ``uple``).

The command is intentionally input-only and streaming.  It keeps compact
records and counters, never reads an LLVM file into one giant string, and does
not fail merely because the two inventories differ.
"""

from __future__ import annotations

import argparse
import collections
import dataclasses
import json
import os
import re
import sys
from pathlib import Path
from typing import Iterable, Iterator, Optional


class InputError(Exception):
    """Malformed command line or malformed LLVM input."""


@dataclasses.dataclass(frozen=True)
class Semantic:
    receiver: Optional[str]
    impl_owner: Optional[str]
    dispatch: str
    method: str
    args: tuple[str, ...]
    block: Optional[str]
    return_type: Optional[str]
    raw: str

    @property
    def positional_args(self) -> tuple[str, ...]:
        return self.args

    @property
    def identity_key(self) -> tuple[object, ...]:
        # Return type is deliberately not an identity component: Crystal does
        # not overload solely by return type.  It is emitted as a separate
        # signature field and can be checked for ABI conflicts by consumers.
        return (
            self.dispatch,
            self.receiver or "",
            self.impl_owner or "",
            self.method,
            self.args,
            bool(self.block),
        )


@dataclasses.dataclass
class SymbolRecord:
    side: str
    body_kind: str
    raw: str
    line: int
    signature_prefix: str
    abi_fingerprint: str = "?"
    llvm_linkage: str = "external"
    debug_name: Optional[str] = None
    category: str = "opaque"
    parse_error: str = ""
    semantic: Optional[Semantic] = None
    reverse_status: str = ""
    reverse_display: str = ""
    reverse_reason: str = ""


@dataclasses.dataclass(frozen=True)
class Candidate:
    raw: str
    tier: str
    logical: str
    provisional: bool = False


TIER_RANK: dict[str, int] = {
    "top_level": 0,
    "impl_full_class": 10,
    "impl_root_class": 20,
    "impl_full": 10,
    "impl_root": 20,
    "receiver_full_class": 30,
    "receiver_full": 30,
    "receiver_root_class": 40,
    "receiver_root": 40,
    "receiver_full_impl_full": 50,
    "receiver_root_impl_full": 60,
    "receiver_full_impl_root": 60,
    "receiver_root_impl_root": 70,
    "raw_exact": -1,
}


def candidate_rank(tier: str) -> int:
    """Deterministic confidence ordering for forward candidates.

    Implementation owners outrank inherited receiver spellings; full owners
    outrank generic roots; non-absolute forms outrank absolute aliases; and
    explicit `@` transport candidates are diagnostic fallbacks.  Unknown ABI
    suffix variants are intentionally lower confidence than their base tier.
    """
    base = tier
    penalty = 0
    # Remove provisional ABI markers before absolute-form suffixes so
    # `receiver_full_absolute_arity1` inherits the receiver rank.
    abi_match = re.search(r"_(?:arity\d+|splat|double_splat|named|positional|noblock|super)(?:_|$)", base)
    if abi_match:
        base = base[: abi_match.start()]
        penalty += 25
    while base.endswith("_absolute_impl"):
        penalty += 5
        base = base[: -len("_absolute_impl")]
    while base.endswith("_absolute"):
        penalty += 5
        base = base[: -len("_absolute")]
    return TIER_RANK.get(base, 100) + penalty


# This is intentionally kept byte-for-byte in the same order as
# TypeMapper#mangle_name_uncached in src/compiler/mir/llvm_backend.cr.
MANGLE_MULTI: tuple[tuple[bytes, str], ...] = (
    (b"<=>", "$CMP"),
    (b"[]=", "$IDXS"),
    (b"[]?", "$IDXQ"),
    (b"<=", "$LE"),
    (b">=", "$GE"),
    (b"==", "$EQ"),
    (b"!=", "$NE"),
    (b"=~", "$MATCH"),
    (b"!~", "$NMATCH"),
    (b"<<", "$SHL"),
    (b">>", "$SHR"),
    (b"**", "$POW"),
    (b"[]", "$IDX"),
    (b"->", "$AR"),
    (b"::", "$CC"),
)

MANGLE_SINGLE: dict[int, str] = {
    ord("<"): "$LT",
    ord(">"): "$GT",
    ord("+"): "$ADD",
    ord("-"): "$SUB",
    ord("*"): "$MUL",
    ord("/"): "$DIV",
    ord("%"): "$MOD",
    ord("&"): "$AND",
    ord("|"): "$OR",
    ord("^"): "$XOR",
    ord("~"): "$NOT",
    ord("="): "$SET",
    ord("!"): "$BANG",
    ord("?"): "$Q",
    ord("("): "$L",
    ord(")"): "$R",
    ord(","): "$C",
    ord("#"): "$H",
    ord("."): "$D",
    ord(" "): "$_",
    ord("@"): "$AT",
    ord("["): "$BL",
    ord("]"): "$BR",
    ord("{"): "$YL",
    ord("}"): "$YR",
    ord(":"): "$CO",
    ord(";"): "$SC",
    ord("'"): "$SQ",
    ord('"'): "$DQ",
    ord("\\"): "$BS",
    ord("$"): "$$",
}

DECODE_TOKENS: tuple[tuple[str, str], ...] = tuple(
    sorted(
        [(encoded, source.decode("latin1")) for source, encoded in MANGLE_MULTI]
        + [(encoded, chr(byte)) for byte, encoded in MANGLE_SINGLE.items()],
        key=lambda item: (-len(item[0]), item[0]),
    )
)

HEX = set("0123456789abcdefABCDEF")
LLVM_FUNCTION_RE = re.compile(
    r"^\s*(define|declare)\b(?P<prefix>.*?)\s@(?P<name>\"(?:\\.|[^\"\\])*\"|[^\s(,]+)\s*\(",
)
DISUBPROGRAM_MARKER_RE = re.compile(r"!DISubprogram\b")
LLVM_QUOTED_RE = r'"(?:\\.|[^"\\])*"'


def parse_disubprogram_metadata(line: str) -> Optional[tuple[str, str]]:
    """Read name/linkageName in either metadata order when on one line."""
    if not DISUBPROGRAM_MARKER_RE.search(line):
        return None
    name_match = re.search(rf"\bname:\s*(?P<name>{LLVM_QUOTED_RE})", line)
    linkage_match = re.search(rf"\blinkageName:\s*(?P<linkage>{LLVM_QUOTED_RE})", line)
    if not name_match or not linkage_match:
        return None
    return decode_llvm_string(linkage_match.group("linkage")), decode_llvm_string(name_match.group("name"))


def decode_llvm_string(value: str) -> str:
    """Decode an LLVM quoted identifier, retaining unknown escapes safely."""
    if len(value) >= 2 and value[0] == '"' and value[-1] == '"':
        value = value[1:-1]
    out: list[str] = []
    i = 0
    while i < len(value):
        if value[i] != "\\":
            out.append(value[i])
            i += 1
            continue
        if i + 2 < len(value) and value[i + 1] in HEX and value[i + 2] in HEX:
            out.append(chr(int(value[i + 1 : i + 3], 16)))
            i += 3
        elif i + 1 < len(value):
            # LLVM accepts escaped punctuation such as \" and \\.
            out.append(value[i + 1])
            i += 2
        else:
            out.append("\\")
            i += 1
    return "".join(out)


def _parameter_text(line: str, opening_index: int) -> str:
    """Extract the balanced LLVM parameter text from one function header."""
    depth = 0
    quoted = False
    escaped = False
    for index in range(opening_index, len(line)):
        ch = line[index]
        if quoted:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                quoted = False
            continue
        if ch == '"':
            quoted = True
        elif ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                return line[opening_index + 1 : index]
    return "?"


def _llvm_tokens(text: str) -> list[str]:
    """Split LLVM header text on whitespace while preserving quoted tokens."""
    tokens: list[str] = []
    current: list[str] = []
    quoted = False
    escaped = False
    for ch in text.strip():
        if quoted:
            current.append(ch)
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                quoted = False
            continue
        if ch == '"':
            quoted = True
            current.append(ch)
        elif ch.isspace():
            if current:
                tokens.append("".join(current))
                current = []
        else:
            current.append(ch)
    if current:
        tokens.append("".join(current))
    return tokens


def _normalize_abi_parameter(text: str) -> str:
    text = re.sub(r"\s+", " ", text.strip())
    if not text:
        return ""
    if text == "...":
        return text
    # SSA names are not ABI identity. Keep named struct types (`%Foo`) while
    # removing a trailing value name (`%arg`) when a parameter has two tokens.
    tokens = _llvm_tokens(text)
    if len(tokens) > 1 and re.fullmatch(r"%(?:\"(?:\\.|[^\"\\])*\"|[A-Za-z0-9._$-]+)", tokens[-1]):
        tokens.pop()
    return " ".join(tokens)


def abi_fingerprint(prefix: str, line: str, opening_index: int) -> str:
    """Produce a stable, compact LLVM ABI signature fingerprint."""
    prefix_tokens = _llvm_tokens(prefix)
    if prefix_tokens and prefix_tokens[0] in {"define", "declare"}:
        prefix_tokens = prefix_tokens[1:]
    return_type = prefix_tokens[-1] if prefix_tokens else "?"
    parameter_text = _parameter_text(line, opening_index)
    if parameter_text == "?":
        return f"{return_type}|?"
    try:
        parameters = split_top_level(parameter_text)
    except ValueError:
        parameters = [parameter_text]
    normalized = [_normalize_abi_parameter(parameter) for parameter in parameters]
    return f"{return_type}|{','.join(normalized)}"


LLVM_LINKAGE_WORDS = {
    "private", "internal", "available_externally", "linkonce", "weak", "common",
    "appending", "extern_weak", "linkonce_odr", "weak_odr", "external",
}


def extract_llvm_linkage(prefix: str) -> str:
    # LLVM_FUNCTION_RE consumes the `define`/`declare` keyword before prefix;
    # the captured text starts with storage/linkage modifiers (or the return
    # type), so do not discard its first token.
    tokens = re.sub(r"\s+", " ", prefix.strip()).split(" ")
    for token in tokens:
        if token in LLVM_LINKAGE_WORDS:
            return token
    return "external"


def mangle_name(name: str) -> str:
    """Forward implementation of Adamas TypeMapper#mangle_name_uncached."""
    if name.startswith("llvm."):
        return name
    data = name.encode("utf-8")
    out: list[str] = []
    i = 0
    while i < len(data):
        remaining = len(data) - i
        matched = False
        for source, token in MANGLE_MULTI:
            if remaining >= len(source) and data[i : i + len(source)] == source:
                out.append(token)
                i += len(source)
                matched = True
                break
        if matched:
            continue
        byte = data[i]
        if (
            ord("a") <= byte <= ord("z")
            or ord("A") <= byte <= ord("Z")
            or ord("0") <= byte <= ord("9")
            or byte == ord("_")
        ):
            out.append(chr(byte))
        elif byte in MANGLE_SINGLE:
            out.append(MANGLE_SINGLE[byte])
        else:
            out.append(f"$x{byte:02x}")
        i += 1
    return "".join(out)


def _top_level_positions(text: str) -> Iterator[tuple[int, str]]:
    """Yield characters at the outer level of (), [], and {} nesting."""
    paren = bracket = brace = 0
    i = 0
    while i < len(text):
        ch = text[i]
        if paren == bracket == brace == 0:
            yield i, ch
        if ch == "(":
            paren += 1
        elif ch == ")":
            paren -= 1
        elif ch == "[":
            bracket += 1
        elif ch == "]":
            bracket -= 1
        elif ch == "{":
            brace += 1
        elif ch == "}":
            brace -= 1
        if paren < 0 or bracket < 0 or brace < 0:
            raise ValueError("unbalanced delimiters")
        i += 1
    if paren or bracket or brace:
        raise ValueError("unbalanced delimiters")


def split_top_level(text: str, separator: str = ",") -> list[str]:
    parts: list[str] = []
    start = 0
    paren = bracket = brace = angle = 0
    i = 0
    while i < len(text):
        ch = text[i]
        if ch == "(":
            paren += 1
        elif ch == ")":
            paren -= 1
        elif ch == "[":
            bracket += 1
        elif ch == "]":
            bracket -= 1
        elif ch == "{":
            brace += 1
        elif ch == "}":
            brace -= 1
        elif ch == "<":
            angle += 1
        elif ch == ">" and angle:
            angle -= 1
        if (
            text.startswith(separator, i)
            and paren == bracket == brace == angle == 0
        ):
            parts.append(text[start:i].strip())
            i += len(separator)
            start = i
            continue
        i += 1
    if paren or bracket or brace or angle:
        raise ValueError("unbalanced type delimiters")
    tail = text[start:].strip()
    if tail or text.strip():
        parts.append(tail)
    return parts


def split_return(text: str) -> tuple[str, Optional[str]]:
    """Split a final single colon, ignoring namespace `::` and nested types."""
    paren = bracket = brace = 0
    for i in range(len(text) - 1, -1, -1):
        ch = text[i]
        if ch == ")":
            paren += 1
        elif ch == "(":
            paren -= 1
        elif ch == "]":
            bracket += 1
        elif ch == "[":
            bracket -= 1
        elif ch == "}":
            brace += 1
        elif ch == "{":
            brace -= 1
        elif ch == ":" and paren == bracket == brace == 0:
            prev_colon = i > 0 and text[i - 1] == ":"
            next_colon = i + 1 < len(text) and text[i + 1] == ":"
            if not prev_colon and not next_colon:
                return text[:i], text[i + 1 :].strip() or None
    return text, None


def split_method_args(text: str) -> tuple[str, Optional[str]]:
    """Find the final `<...>` argument list, preserving operator `<` names."""
    if text.endswith("<=>"):
        return text, None
    if not text.endswith(">"):
        return text, None
    depth = 0
    for i in range(len(text) - 1, -1, -1):
        ch = text[i]
        if ch == ">":
            depth += 1
        elif ch == "<":
            depth -= 1
            if depth == 0:
                return text[:i], text[i + 1 : -1]
            if depth < 0:
                break
    return text, None


def split_owner_method(text: str) -> tuple[Optional[str], str, str]:
    """Return receiver, method, and dispatch from an original logical name."""
    candidates: list[tuple[int, str, int]] = []
    paren = bracket = brace = 0
    i = 0
    while i < len(text):
        ch = text[i]
        if paren == bracket == brace == 0:
            if ch == "#":
                candidates.append((i, "#", 1))
            elif text.startswith("::", i):
                candidates.append((i, "::", 2))
        if ch == "(":
            paren += 1
        elif ch == ")":
            paren -= 1
        elif ch == "[":
            bracket += 1
        elif ch == "]":
            bracket -= 1
        elif ch == "{":
            brace += 1
        elif ch == "}":
            brace -= 1
        i += 1
    if not candidates:
        return None, text, "top_level"
    index, separator, width = candidates[-1]
    owner = text[:index]
    method = text[index + width :]
    if not owner or not method:
        raise ValueError("missing owner or method")
    return owner, method, "instance" if separator == "#" else "class"


def split_impl_owner(owner: Optional[str]) -> tuple[Optional[str], Optional[str]]:
    if owner is None:
        return None, None
    paren = bracket = brace = 0
    for i, ch in enumerate(owner):
        if ch == "(":
            paren += 1
        elif ch == ")":
            paren -= 1
        elif ch == "[":
            bracket += 1
        elif ch == "]":
            bracket -= 1
        elif ch == "{":
            brace += 1
        elif ch == "}":
            brace -= 1
        elif ch == "@" and paren == bracket == brace == 0:
            return owner[:i], owner[i + 1 :] or None
    return owner, None


def parse_original_name(raw: str) -> Semantic:
    if not raw.startswith("*"):
        raise ValueError("original semantic name must start with *")
    body = raw[1:]
    body, return_type = split_return(body)
    body, arg_text = split_method_args(body)
    try:
        receiver_text, method, dispatch = split_owner_method(body)
    except ValueError as exc:
        raise ValueError(str(exc)) from exc
    receiver, impl_owner = split_impl_owner(receiver_text)
    args: list[str] = []
    block: Optional[str] = None
    if arg_text is not None and arg_text.strip():
        for arg in split_top_level(arg_text):
            if not arg:
                raise ValueError("empty method argument")
            if arg.startswith("&"):
                if block is not None:
                    raise ValueError("multiple block arguments")
                block = arg[1:].strip() or "block"
            else:
                args.append(arg)
    if not method:
        raise ValueError("empty method name")
    return Semantic(receiver, impl_owner, dispatch, method, tuple(args), block, return_type, raw)


def root_type(type_name: Optional[str]) -> Optional[str]:
    if not type_name:
        return type_name
    text = type_name.strip()
    paren = bracket = brace = 0
    for i, ch in enumerate(text):
        if ch == "(":
            if paren == bracket == brace == 0:
                close = text.rfind(")")
                if close == len(text) - 1:
                    return text[:i]
                return text
            paren += 1
        elif ch == ")":
            paren -= 1
        elif ch == "[":
            bracket += 1
        elif ch == "]":
            bracket -= 1
        elif ch == "{":
            brace += 1
        elif ch == "}":
            brace -= 1
    return text


def _strip_outer_type_parens(text: str) -> str:
    while text.startswith("(") and text.endswith(")"):
        depth = 0
        encloses = True
        for index, ch in enumerate(text):
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
                if depth == 0 and index != len(text) - 1:
                    encloses = False
                    break
        if encloses and depth == 0:
            text = text[1:-1].strip()
        else:
            break
    return text


def normalize_type_for_mangle(type_name: str) -> str:
    """Mirror Adamas union ordering and recursively canonicalize generic args."""
    text = _strip_outer_type_parens(type_name.strip())
    try:
        union_parts = split_top_level(text, "|")
    except ValueError:
        union_parts = [text]
    if len(union_parts) > 1:
        arms = []
        for part in union_parts:
            arm = normalize_type_for_mangle(part)
            if arm and arm not in arms:
                arms.append(arm)
        nil_arms = sorted(arm for arm in arms if arm == "Nil" or arm.endswith("::Nil"))
        other_arms = sorted(arm for arm in arms if arm not in nil_arms)
        return " | ".join(nil_arms + other_arms)
    # Legacy Adamas accepts `A___B` as a top-level union spelling.
    if "___" in text and "(" not in text:
        return normalize_type_for_mangle(text.replace("___", " | "))
    paren = bracket = brace = 0
    for index, ch in enumerate(text):
        if ch == "(":
            if paren == bracket == brace == 0 and text.endswith(")"):
                base = text[:index].strip()
                inner = text[index + 1 : -1]
                try:
                    args = split_top_level(inner)
                except ValueError:
                    return text
                return f"{base}({', '.join(normalize_type_for_mangle(arg) for arg in args)})"
            paren += 1
        elif ch == ")":
            paren -= 1
        elif ch == "[":
            bracket += 1
        elif ch == "]":
            bracket -= 1
        elif ch == "{":
            brace += 1
        elif ch == "}":
            brace -= 1
    return text


def forward_candidates(semantic: Semantic) -> list[Candidate]:
    """Generate exact Adamas raw names in descending confidence tiers."""
    positional_args = tuple(normalize_type_for_mangle(arg) for arg in semantic.positional_args)
    if semantic.block:
        positional_suffix = "_".join(positional_args)
        suffix = "block" if not positional_suffix else f"{positional_suffix}_block"
    elif positional_args:
        suffix = "_".join(positional_args)
    else:
        suffix = ""

    def make_base(owner: Optional[str], dispatch: str, impl: Optional[str] = None) -> str:
        if dispatch == "top_level":
            return semantic.method
        if owner is None:
            return semantic.method
        if dispatch == "class":
            return f"{owner}.{semantic.method}"
        if impl:
            return f"{owner}@{impl}#{semantic.method}"
        return f"{owner}#{semantic.method}"

    def make_candidates(base: str, tier: str) -> list[Candidate]:
        logical = base if not suffix else f"{base}${suffix}"
        variants: list[tuple[str, str]] = [(logical, "")]
        arity = len(positional_args)
        positional_suffix = "_".join(positional_args)
        if arity == 0 and semantic.dispatch != "top_level":
            variants.append((f"{base}$arity0", "_arity0"))
            if semantic.block:
                variants.append((f"{base}$block$arity0", "_arity0_block"))
        if arity > 0:
            # `function_full_name_for_def` uses `$arityN` for partially or
            # untyped method signatures, after the typed suffix when present.
            variants.append((f"{base}$arity{arity}", f"_arity{arity}"))
            if suffix:
                variants.append((f"{logical}$arity{arity}", f"_arity{arity}_typed"))
            if semantic.block:
                block_arity = f"{base}${positional_suffix}$arity{arity}_block"
                variants.append((block_arity, f"_arity{arity}_block"))
        for shape in ("splat", "double_splat"):
            shaped = f"{logical}_{shape}"
            variants.append((shaped, f"_{shape}"))
            if arity > 0:
                variants.append((f"{logical}$arity{arity}_{shape}", f"_arity{arity}_{shape}"))
        for collision_suffix in ("_named", "_positional", "_noblock"):
            variants.append((f"{logical}{collision_suffix}", collision_suffix))
        return [Candidate(mangle_name(candidate_logical), tier + marker, candidate_logical, bool(marker)) for candidate_logical, marker in variants]

    if semantic.dispatch == "top_level":
        return make_candidates(make_base(None, "top_level"), "top_level")

    receiver_full = normalize_type_for_mangle(semantic.receiver) if semantic.receiver else semantic.receiver
    receiver_root = root_type(receiver_full)
    impl_full = normalize_type_for_mangle(semantic.impl_owner) if semantic.impl_owner else semantic.impl_owner
    impl_root = root_type(impl_full)
    candidates_by_raw: dict[str, Candidate] = {}

    def add(owner: Optional[str], tier: str, impl: Optional[str] = None) -> None:
        owner_forms: list[tuple[Optional[str], str]] = [(owner, tier)]
        if owner and not owner.startswith("::"):
            owner_forms.append((f"::{owner}", f"{tier}_absolute"))
        impl_forms: list[tuple[Optional[str], str]] = [(impl, "")]
        if impl and not impl.startswith("::"):
            impl_forms.append((f"::{impl}", "_absolute_impl"))
        for owner_form, owner_tier in owner_forms:
            for impl_form, impl_tier in impl_forms:
                for candidate in make_candidates(make_base(owner_form, semantic.dispatch, impl_form), owner_tier + impl_tier):
                    existing = candidates_by_raw.get(candidate.raw)
                    if existing is None or (candidate_rank(candidate.tier), candidate.tier) < (candidate_rank(existing.tier), existing.tier):
                        candidates_by_raw[candidate.raw] = candidate

    if semantic.dispatch == "class":
        for owner, tier in (
            (receiver_full, "receiver_full_class"),
            (receiver_root, "receiver_root_class"),
        ):
            if owner:
                add(owner, tier)
        if impl_full:
            add(impl_full, "impl_full_class")
            if impl_root != impl_full:
                add(impl_root, "impl_root_class")
        return sorted(candidates_by_raw.values(), key=lambda candidate: (candidate_rank(candidate.tier), candidate.tier, candidate.raw))

    if impl_full:
        combos = (
            (receiver_full, impl_full, "receiver_full_impl_full"),
            (receiver_root, impl_full, "receiver_root_impl_full"),
            (receiver_full, impl_root, "receiver_full_impl_root"),
            (receiver_root, impl_root, "receiver_root_impl_root"),
        )
        for owner, impl, tier in combos:
            if owner and impl:
                add(owner, tier, impl)
        if receiver_full:
            add(receiver_full, "receiver_full")
        if receiver_root != receiver_full:
            add(receiver_root, "receiver_root")
        # Adamas materializes the implementation owner, not the inherited
        # receiver, in the common case.  Keep these as lower-confidence tiers.
        add(impl_full, "impl_full")
        if impl_root != impl_full:
            add(impl_root, "impl_root")
    else:
        add(receiver_full, "receiver_full")
        if receiver_root != receiver_full:
            add(receiver_root, "receiver_root")
    return sorted(candidates_by_raw.values(), key=lambda candidate: (candidate_rank(candidate.tier), candidate.tier, candidate.raw))


def _decode_options(raw: str, position: int) -> list[tuple[int, str]]:
    options: list[tuple[int, str]] = []
    for encoded, source in DECODE_TOKENS:
        if raw.startswith(encoded, position):
            options.append((len(encoded), source))
    if raw.startswith("$x", position) and position + 3 < len(raw):
        if raw[position + 2] in HEX and raw[position + 3] in HEX:
            options.append((4, chr(int(raw[position + 2 : position + 4], 16))))
    return options


def decode_adamas_display(raw: str) -> tuple[str, str, str]:
    """Return best-effort display, status, and reason.

    The shortest `$L` option is preferred when it is followed by an uppercase
    identifier.  This keeps `Array$LTuple` readable as `Array(Tuple)` while the
    status remains `ambiguous`; no caller should use this string for identity.
    """
    out: list[str] = []
    reasons: list[str] = []
    ambiguous = False
    malformed = False
    i = 0
    while i < len(raw):
        if raw[i] != "$":
            out.append(raw[i])
            i += 1
            continue
        options = _decode_options(raw, i)
        if not options:
            malformed = True
            reasons.append(f"unknown_token@{i}")
            out.append("<malformed>")
            i += 1
            continue
        if len(options) > 1:
            ambiguous = True
            reasons.append(f"non_prefix_token@{i}")
        # Default to longest token, except the known `($Type` ambiguity where
        # the shorter opening-paren interpretation preserves valid type syntax.
        chosen = max(options, key=lambda item: item[0])
        short_l = next((item for item in options if item[1] == "("), None)
        if short_l:
            # Inspect the character after the *short* token. In `$LTuple`,
            # it is `T`, while the longest `$LT` interpretation leaves
            # `uple` after an opening `<`.
            short_next = raw[i + short_l[0] : i + short_l[0] + 1]
            if short_next and (short_next[0].isupper() or short_next[0] == "_"):
                chosen = short_l
        out.append(chosen[1])
        i += chosen[0]
    status = "malformed" if malformed else ("ambiguous" if ambiguous else "ok")
    return "".join(out), status, ";".join(reasons)


def classify_symbol(raw: str, body_kind: str, side: str) -> str:
    if raw.startswith("__vdispatch__"):
        return "vdispatch"
    if raw.startswith("__crystal_block_proc_") or raw.startswith("__adamas_block_proc_"):
        return "closure"
    if raw.startswith("~proc") or raw.startswith("__crystal_proc_") or raw.startswith("__adamas_proc_"):
        return "proc"
    if raw.startswith("~") and ("proc" in raw or "match" in raw or "metaclass" in raw):
        return "closure"
    if raw in {"main", "_main", "__crystal_main", "__adamas_main"} or raw.startswith("__adamas_entry"):
        return "entry"
    if raw.startswith("llvm.") or raw.startswith("__crystal_") or raw.startswith("__adamas_"):
        return "runtime"
    if side == "adamas" and adamas_abi_variant(raw):
        return "abi_variant"
    if side == "original" and raw.startswith("*"):
        # Crystal can prefix local/nested declarations with their source path
        # (e.g. `*/opt/.../raise.cr::LEBReader`).  A slash in an operator
        # method is not path evidence, so only inspect the owner prefix before
        # the first top-level `#`/`::` separator.
        body = raw[1:]
        separator_positions = [pos for pos in (body.find("#"), body.find("::")) if pos >= 0]
        owner_prefix = body[: min(separator_positions)] if separator_positions else body
        if "/" in owner_prefix or "\\" in owner_prefix:
            return "path_generated"
    if raw.startswith("*"):
        return "semantic"
    if side == "adamas" and "$" in raw:
        return "semantic"
    if body_kind == "declare":
        return "extern"
    return "opaque"


def adamas_abi_variant(raw: str) -> bool:
    """Recognize backend-generated ABI-shape suffixes without reverse identity."""
    base, separator, suffix = raw.partition("$$")
    if re.search(r"(?:^|_)(?:splat|double_splat|named|positional|noblock)$", base):
        return True
    if not separator:
        return base.endswith("_super") or base.endswith("_splat") or base.endswith("_double_splat")
    if re.search(r"(?:^|_)arity\d+(?:_|$)", suffix):
        return True
    if re.search(r"(?:^|_)(?:splat|double_splat|named|positional|noblock)(?:_|$)", suffix):
        return True
    if re.search(r"(?:^|_)super(?:_|$)", suffix):
        return True
    return base.endswith("_super")


def parse_adamas_file(path: Path, side: str) -> list[SymbolRecord]:
    records: list[SymbolRecord] = []
    metadata: dict[str, str] = {}
    malformed_lines = 0
    try:
        with path.open("r", encoding="utf-8", errors="replace") as stream:
            for line_no, line in enumerate(stream, 1):
                metadata_pair = parse_disubprogram_metadata(line)
                if metadata_pair:
                    linkage, name = metadata_pair
                    metadata[linkage] = name
                match = LLVM_FUNCTION_RE.match(line)
                if not match:
                    if re.match(r"^\s*(?:define|declare)\b", line):
                        malformed_lines += 1
                    continue
                raw = decode_llvm_string(match.group("name"))
                record = SymbolRecord(
                    side=side,
                    body_kind=match.group(1),
                    raw=raw,
                    line=line_no,
                    signature_prefix=match.group("prefix").strip(),
                    abi_fingerprint=abi_fingerprint(match.group("prefix"), line, match.end() - 1),
                    llvm_linkage=extract_llvm_linkage(match.group("prefix")),
                )
                record.category = classify_symbol(raw, record.body_kind, side)
                if side == "original" and record.category == "semantic":
                    try:
                        record.semantic = parse_original_name(raw)
                    except ValueError as exc:
                        record.category = "opaque"
                        record.parse_error = str(exc)
                        record.reverse_status = "malformed"
                        record.reverse_reason = str(exc)
                elif side == "adamas" and record.category in {"semantic", "abi_variant"}:
                    display, status, reason = decode_adamas_display(raw)
                    record.reverse_display = display
                    record.reverse_status = status
                    record.reverse_reason = reason
                records.append(record)
    except OSError as exc:
        raise InputError(f"cannot read {path}: {exc}") from exc
    for record in records:
        record.debug_name = metadata.get(record.raw)
    if malformed_lines:
        raise InputError(f"{path}: {malformed_lines} define/declare lines lack a parseable @identifier")
    return records


def tsv_value(value: object) -> str:
    if value is None:
        return ""
    if isinstance(value, (tuple, list)):
        return ",".join(tsv_value(item) for item in value)
    return str(value).replace("\t", " ").replace("\r", " ").replace("\n", " ")


def semantic_display(semantic: Optional[Semantic]) -> str:
    if semantic is None:
        return ""
    owner = semantic.receiver or ""
    if semantic.impl_owner:
        owner = f"{owner}@{semantic.impl_owner}"
    if semantic.dispatch == "instance":
        prefix = f"{owner}#" if owner else ""
    elif semantic.dispatch == "class":
        prefix = f"{owner}::" if owner else ""
    else:
        prefix = ""
    args = list(semantic.args)
    if semantic.block:
        args.append(f"&{semantic.block}")
    arg_text = f"<{', '.join(args)}>" if args else ""
    ret = f":{semantic.return_type}" if semantic.return_type else ""
    return f"{prefix}{semantic.method}{arg_text}{ret}"


def write_tsv(path: Path, header: Iterable[str], rows: Iterable[Iterable[object]]) -> None:
    try:
        with path.open("w", encoding="utf-8", newline="") as stream:
            stream.write("\t".join(header) + "\n")
            for row in rows:
                stream.write("\t".join(tsv_value(value) for value in row) + "\n")
    except OSError as exc:
        raise InputError(f"cannot write {path}: {exc}") from exc


def record_key(record: SymbolRecord) -> tuple[object, ...]:
    return record.semantic.identity_key if record.semantic else (record.raw,)


def summarize(records: list[SymbolRecord]) -> dict[str, object]:
    by_body_kind = collections.Counter(record.body_kind for record in records)
    by_category = collections.Counter(record.category for record in records)
    return {
        "total": len(records),
        "define": by_body_kind.get("define", 0),
        "declare": by_body_kind.get("declare", 0),
        "parse_errors": sum(1 for record in records if record.parse_error),
        "categories": dict(sorted(by_category.items())),
    }


def top_counter(records: Iterable[SymbolRecord], attr: str, top: int) -> list[dict[str, object]]:
    counter: collections.Counter[str] = collections.Counter()
    for record in records:
        semantic = record.semantic
        if semantic is None:
            continue
        value = getattr(semantic, attr)
        if value:
            counter[str(value)] += 1
    return [{"name": name, "count": count} for name, count in sorted(counter.items(), key=lambda item: (-item[1], item[0]))[:top]]


def adamas_family_histogram(records: Iterable[SymbolRecord], top: int) -> list[dict[str, object]]:
    """Count raw Adamas overload families without reverse-decoding identity."""
    counter: collections.Counter[tuple[str, str]] = collections.Counter()
    for record in records:
        if record.category == "vdispatch":
            family = re.sub(r"\$\$T\d+$", "", record.raw)
        elif record.category in {"semantic", "abi_variant"}:
            family = record.raw.split("$$", 1)[0]
        else:
            continue
        counter[(record.category, family)] += 1
    return [
        {"category": category, "family": family, "count": count}
        for (category, family), count in sorted(counter.items(), key=lambda item: (-item[1], item[0]))[:top]
    ]


def match_tsv_row(item: dict[str, object]) -> list[object]:
    original: SymbolRecord = item["original"]  # type: ignore[assignment]
    adamas: SymbolRecord = item["adamas"]  # type: ignore[assignment]
    candidate: Candidate = item["candidate"]  # type: ignore[assignment]
    semantic = original.semantic
    if original.body_kind == adamas.body_kind:
        body_state = "same"
    elif original.body_kind == "define" and adamas.body_kind == "declare":
        body_state = "define_to_declare"
    elif original.body_kind == "declare" and adamas.body_kind == "define":
        body_state = "declare_to_define"
    else:
        body_state = f"{original.body_kind}_to_{adamas.body_kind}"
    if original.abi_fingerprint == "?" or adamas.abi_fingerprint == "?":
        abi_state = "unknown"
    elif original.abi_fingerprint == adamas.abi_fingerprint:
        abi_state = "same"
    else:
        abi_state = "mismatch"
    linkage_state = "same" if original.llvm_linkage == adamas.llvm_linkage else "mismatch"
    return [
        original.raw,
        adamas.raw,
        original.body_kind,
        candidate.tier,
        adamas.category,
        body_state,
        abi_state,
        original.abi_fingerprint,
        adamas.abi_fingerprint,
        linkage_state,
        original.llvm_linkage,
        adamas.llvm_linkage,
        semantic.receiver if semantic else "",
        semantic.impl_owner if semantic else "",
        semantic.dispatch if semantic else "",
        semantic.method if semantic else "",
        semantic.args if semantic else "",
        semantic.block if semantic else "",
        semantic.return_type if semantic else "",
        original.line,
        adamas.line,
        original.debug_name,
        adamas.debug_name,
    ]


def abi_state_for_item(item: dict[str, object]) -> str:
    original: SymbolRecord = item["original"]  # type: ignore[assignment]
    adamas: SymbolRecord = item["adamas"]  # type: ignore[assignment]
    if original.abi_fingerprint == "?" or adamas.abi_fingerprint == "?":
        return "unknown"
    return "same" if original.abi_fingerprint == adamas.abi_fingerprint else "mismatch"


def run(args: argparse.Namespace) -> int:
    original_path = Path(args.original_ll)
    adamas_path = Path(args.adamas_ll)
    if not original_path.is_file():
        raise InputError(f"original LLVM input not found: {original_path}")
    if not adamas_path.is_file():
        raise InputError(f"Adamas LLVM input not found: {adamas_path}")
    if args.top < 0:
        raise InputError("--top must be non-negative")
    original = parse_adamas_file(original_path, "original")
    adamas = parse_adamas_file(adamas_path, "adamas")

    adamas_by_raw: dict[str, list[SymbolRecord]] = collections.defaultdict(list)
    for record in adamas:
        adamas_by_raw[record.raw].append(record)

    matches: list[dict[str, object]] = []
    provisional_matches: list[dict[str, object]] = []
    original_only: list[SymbolRecord] = []
    matched_adamas: set[int] = set()
    adamas_origins: dict[int, list[str]] = collections.defaultdict(list)
    ambiguous: list[tuple[SymbolRecord, str, str]] = []
    collisions: list[tuple[str, str, str, int, str]] = []
    original_semantic_keys: dict[tuple[object, ...], list[SymbolRecord]] = collections.defaultdict(list)
    adamas_raw_keys: dict[tuple[str, str], list[SymbolRecord]] = collections.defaultdict(list)
    adamas_raw_all: dict[str, list[SymbolRecord]] = collections.defaultdict(list)
    for record in original:
        if record.semantic:
            original_semantic_keys[record.semantic.identity_key].append(record)
    for record in adamas:
        adamas_raw_keys[(record.body_kind, record.raw)].append(record)
        adamas_raw_all[record.raw].append(record)

    for key, records in sorted(original_semantic_keys.items(), key=lambda item: repr(item[0])):
        if len(records) > 1:
            collisions.append(("semantic_duplicate", "original", semantic_display(records[0].semantic), len(records), ""))
    for key, records in sorted(adamas_raw_keys.items()):
        if len(records) > 1:
            collisions.append(("raw_duplicate", "adamas", key[1], len(records), key[0]))
    for raw, records in sorted(adamas_raw_all.items()):
        if len({record.body_kind for record in records}) > 1:
            collisions.append(("raw_duplicate_cross_body_kind", "adamas", raw, len(records), ",".join(sorted({record.body_kind for record in records}))))

    def choose_raw_hit(raw: str, body_kind: str) -> tuple[Optional[SymbolRecord], list[SymbolRecord]]:
        all_hits = adamas_by_raw.get(raw, [])
        same_body_kind = [record for record in all_hits if record.body_kind == body_kind]
        if same_body_kind:
            return same_body_kind[0], same_body_kind
        return (all_hits[0], all_hits) if all_hits else (None, [])

    def register_match(original_record: SymbolRecord, adamas_record: SymbolRecord, candidate: Candidate) -> None:
        matched_adamas.add(id(adamas_record))
        matches.append({"original": original_record, "adamas": adamas_record, "candidate": candidate})
        prior = adamas_origins[id(adamas_record)]
        if prior:
            collisions.append(("many_original_one_adamas", "both", adamas_record.raw, len(prior) + 1, ",".join(prior + [original_record.raw])))
        prior.append(original_record.raw)

    def register_provisional(original_record: SymbolRecord, adamas_record: SymbolRecord, candidate: Candidate) -> None:
        matched_adamas.add(id(adamas_record))
        provisional_matches.append({"original": original_record, "adamas": adamas_record, "candidate": candidate})
        prior = adamas_origins[id(adamas_record)]
        if prior:
            collisions.append(("many_original_one_adamas_provisional", "both", adamas_record.raw, len(prior) + 1, ",".join(prior + [original_record.raw])))
        prior.append(original_record.raw)

    for original_record in original:
        semantic = original_record.semantic
        if semantic is None:
            # Runtime/extern/generated rows have no source-level identity, but
            # an exact `(linkage, raw)` match is still useful and must not make
            # common declarations look like semantic drift.
            chosen, raw_hits = choose_raw_hit(original_record.raw, original_record.body_kind)
            if chosen is not None:
                if len(raw_hits) > 1:
                    collisions.append(("raw_match_multiplicity", "adamas", original_record.raw, len(raw_hits), original_record.body_kind))
                register_match(original_record, chosen, Candidate(original_record.raw, "raw_exact", original_record.raw))
            else:
                original_only.append(original_record)
            continue
        candidates = forward_candidates(semantic)
        hits: dict[str, list[tuple[Candidate, SymbolRecord]]] = collections.defaultdict(list)
        for candidate in candidates:
            chosen, raw_hits = choose_raw_hit(candidate.raw, original_record.body_kind)
            if chosen is not None:
                hits[candidate.raw].append((candidate, chosen))
                if len(raw_hits) > 1:
                    collisions.append(("raw_match_multiplicity", "adamas", candidate.raw, len(raw_hits), original_record.raw))
        authoritative_hits = {
            raw: entries for raw, entries in hits.items() if any(not candidate.provisional for candidate, _ in entries)
        }
        provisional_hits = {
            raw: entries for raw, entries in hits.items() if all(candidate.provisional for candidate, _ in entries)
        }

        def ranked_hit_entries(hit_map: dict[str, list[tuple[Candidate, SymbolRecord]]]) -> list[tuple[int, str, str, Candidate, SymbolRecord]]:
            return sorted(
                (candidate_rank(candidate.tier), candidate.tier, raw, candidate, record)
                for raw, entries in hit_map.items()
                for candidate, record in entries
            )

        if authoritative_hits:
            ranked_hits = ranked_hit_entries(authoritative_hits)
            _, _, _, primary_candidate, primary_record = ranked_hits[0]
            best_rank = ranked_hits[0][0]
            best_hits = [entry for entry in ranked_hits if entry[0] == best_rank]
            if len(authoritative_hits) > 1:
                detail = ";".join(f"{raw}:{candidate.tier}:rank={candidate_rank(candidate.tier)}" for _, _, raw, candidate, _ in ranked_hits)
                reason = "candidate_tie" if len(best_hits) > 1 else "candidate_fanout"
                collisions.append((reason, "both", original_record.raw, len(authoritative_hits), f"selected={primary_candidate.tier};{detail}"))
                ambiguous.append((original_record, reason, detail))
            register_match(original_record, primary_record, primary_candidate)
            # Lower-confidence ABI-shape hits are retained as report-only
            # evidence; they never override an authoritative identity match.
            for _, _, _, candidate, record in ranked_hit_entries(provisional_hits):
                register_provisional(original_record, record, candidate)
        elif provisional_hits:
            ranked_hits = ranked_hit_entries(provisional_hits)
            _, _, _, primary_candidate, primary_record = ranked_hits[0]
            register_provisional(original_record, primary_record, primary_candidate)
        else:
            original_only.append(original_record)

    adamas_only = [record for record in adamas if id(record) not in matched_adamas]
    # Reverse-display ambiguity is useful even for matched records, but retain
    # only semantic, non-generated rows in ambiguous.tsv to keep the report
    # actionable.
    for record in adamas:
        if record.category == "semantic" and record.reverse_status in {"ambiguous", "malformed"}:
            ambiguous.append((record, record.reverse_status, record.reverse_reason))

    try:
        out_dir = Path(args.out_dir)
        out_dir.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        raise InputError(f"cannot create output directory {args.out_dir}: {exc}") from exc

    write_tsv(
        out_dir / "matches.tsv",
        [
            "original_raw",
            "adamas_raw",
            "body_kind",
            "match_tier",
            "category",
            "body_state",
            "abi_state",
            "original_abi",
            "adamas_abi",
            "linkage_state",
            "original_llvm_linkage",
            "adamas_llvm_linkage",
            "receiver",
            "impl_owner",
            "dispatch",
            "method",
            "args",
            "block",
            "return",
            "original_line",
            "adamas_line",
            "original_debug_name",
            "adamas_debug_name",
        ],
        (
            match_tsv_row(item)
            for item in sorted(matches, key=lambda item: (item["original"].raw, item["adamas"].raw))
        ),
    )
    write_tsv(
        out_dir / "provisional_matches.tsv",
        [
            "original_raw", "adamas_raw", "body_kind", "match_tier", "category", "body_state",
            "abi_state", "original_abi", "adamas_abi", "linkage_state", "original_llvm_linkage", "adamas_llvm_linkage", "receiver", "impl_owner", "dispatch",
            "method", "args", "block", "return", "original_line", "adamas_line", "original_debug_name", "adamas_debug_name",
        ],
        (
            match_tsv_row(item)
            for item in sorted(provisional_matches, key=lambda item: (item["original"].raw, item["adamas"].raw, item["candidate"].tier))
        ),
    )
    abi_conflicts: list[dict[str, object]] = []
    for item in matches + provisional_matches:
        original_record: SymbolRecord = item["original"]  # type: ignore[assignment]
        adamas_record: SymbolRecord = item["adamas"]  # type: ignore[assignment]
        if original_record.abi_fingerprint != "?" and adamas_record.abi_fingerprint != "?" and original_record.abi_fingerprint != adamas_record.abi_fingerprint:
            abi_conflicts.append(item)
    write_tsv(
        out_dir / "abi_conflicts.tsv",
        ["original_raw", "adamas_raw", "body_kind", "match_tier", "original_abi", "adamas_abi", "original_line", "adamas_line"],
        (
            [
                item["original"].raw,
                item["adamas"].raw,
                item["original"].body_kind,
                item["candidate"].tier,
                item["original"].abi_fingerprint,
                item["adamas"].abi_fingerprint,
                item["original"].line,
                item["adamas"].line,
            ]
            for item in sorted(abi_conflicts, key=lambda item: (item["original"].raw, item["adamas"].raw, item["original"].line))
        ),
    )
    write_tsv(
        out_dir / "original_only.tsv",
        ["raw", "body_kind", "category", "parse_error", "semantic", "receiver", "impl_owner", "dispatch", "method", "args", "block", "return", "line"],
        (
            [
                record.raw,
                record.body_kind,
                record.category,
                record.parse_error,
                semantic_display(record.semantic),
                record.semantic.receiver if record.semantic else "",
                record.semantic.impl_owner if record.semantic else "",
                record.semantic.dispatch if record.semantic else "",
                record.semantic.method if record.semantic else "",
                record.semantic.args if record.semantic else "",
                record.semantic.block if record.semantic else "",
                record.semantic.return_type if record.semantic else "",
                record.line,
            ]
            for record in sorted(original_only, key=lambda record: (record.raw, record.line))
        ),
    )
    write_tsv(
        out_dir / "adamas_only.tsv",
        ["raw", "body_kind", "category", "display", "reverse_status", "reverse_reason", "line", "debug_name"],
        (
            [record.raw, record.body_kind, record.category, record.reverse_display, record.reverse_status, record.reverse_reason, record.line, record.debug_name]
            for record in sorted(adamas_only, key=lambda record: (record.raw, record.line))
        ),
    )
    write_tsv(
        out_dir / "collisions.tsv",
        ["reason", "side", "key", "multiplicity", "body_kind_or_candidates"],
        (row for row in sorted(collisions)),
    )
    write_tsv(
        out_dir / "ambiguous.tsv",
        ["kind", "side", "raw", "category", "status_or_reason", "detail", "line"],
        (
            [
                "unresolved" if reason in {"candidate_collision", "candidate_tie"} else "display",
                item.side,
                item.raw,
                item.category,
                reason,
                detail,
                item.line,
            ]
            for item, reason, detail in sorted(ambiguous, key=lambda item: (item[0].side, item[0].raw, item[1], item[0].line))
        ),
    )

    original_summary = summarize(original)
    adamas_summary = summarize(adamas)
    adamas_families = adamas_family_histogram(adamas, args.top)
    unresolved_ambiguities = sum(1 for _, reason, _ in ambiguous if reason in {"candidate_collision", "candidate_tie"})
    display_ambiguities = sum(1 for _, reason, _ in ambiguous if reason == "ambiguous")
    display_malformed = sum(1 for _, reason, _ in ambiguous if reason == "malformed")
    summary: dict[str, object] = {
        "schema": 1,
        "inputs": {
            "original_ll": str(original_path),
            "adamas_ll": str(adamas_path),
        },
        "original": original_summary,
        "adamas": adamas_summary,
        "original_llvm_linkage": dict(sorted(collections.Counter(record.llvm_linkage for record in original).items())),
        "adamas_llvm_linkage": dict(sorted(collections.Counter(record.llvm_linkage for record in adamas).items())),
        "matches": len(matches),
        "provisional_matches": len(provisional_matches),
        "provisional_collisions": sum(1 for row in collisions if row[0] == "many_original_one_adamas_provisional"),
        "matched_pairs": len(matches),
        "matched_original_unique": len({id(item["original"]) for item in matches}),
        "matched_adamas_unique": len({id(item["adamas"]) for item in matches}),
        "original_only": len(original_only),
        "adamas_only": len(adamas_only),
        "collisions": len(collisions),
        "ambiguous": unresolved_ambiguities,
        "ambiguous_rows": len(ambiguous),
        "display_ambiguities": display_ambiguities,
        "display_malformed": display_malformed,
        "abi_states": dict(sorted(collections.Counter(abi_state_for_item(item) for item in matches + provisional_matches).items())),
        "abi_mismatches": len(abi_conflicts),
        "linkage_states": dict(sorted(collections.Counter(
            "same" if item["original"].llvm_linkage == item["adamas"].llvm_linkage else "mismatch"
            for item in matches + provisional_matches
        ).items())),
        "match_tiers": dict(sorted(collections.Counter(item["candidate"].tier for item in matches).items())),
        "body_states": dict(sorted(collections.Counter(
            "same"
            if item["original"].body_kind == item["adamas"].body_kind
            else f"{item['original'].body_kind}_to_{item['adamas'].body_kind}"
            for item in matches
        ).items())),
        "top": {
            "original_owners": top_counter(original, "receiver", args.top),
            "original_methods": top_counter(original, "method", args.top),
            "original_only_owners": top_counter(original_only, "receiver", args.top),
            "original_only_methods": top_counter(original_only, "method", args.top),
            "adamas_families": adamas_families,
            "adamas_only_families": adamas_family_histogram(adamas_only, args.top),
        },
        "notes": [
            "Returns are outside identity; compare ABI/signature fields separately.",
            "Adamas reverse decoding is display-only and non-prefix-free tokens are flagged.",
            "define and declare counts/matches are kept separate.",
        ],
    }
    try:
        with (out_dir / "summary.json").open("w", encoding="utf-8") as stream:
            json.dump(summary, stream, indent=2, sort_keys=True)
            stream.write("\n")
    except OSError as exc:
        raise InputError(f"cannot write {out_dir / 'summary.json'}: {exc}") from exc

    summary_rows = [
        ("schema", summary["schema"]),
        ("original_total", original_summary["total"]),
        ("original_define", original_summary["define"]),
        ("original_declare", original_summary["declare"]),
        ("adamas_total", adamas_summary["total"]),
        ("adamas_define", adamas_summary["define"]),
        ("adamas_declare", adamas_summary["declare"]),
        ("matches", len(matches)),
        ("provisional_matches", len(provisional_matches)),
        ("provisional_collisions", summary["provisional_collisions"]),
        ("original_only", len(original_only)),
        ("adamas_only", len(adamas_only)),
        ("collisions", len(collisions)),
        ("ambiguous", unresolved_ambiguities),
        ("ambiguous_rows", len(ambiguous)),
        ("display_ambiguities", display_ambiguities),
        ("display_malformed", display_malformed),
        ("matched_pairs", len(matches)),
        ("matched_original_unique", len({id(item["original"]) for item in matches})),
        ("matched_adamas_unique", len({id(item["adamas"]) for item in matches})),
        ("abi_mismatches", len(abi_conflicts)),
        ("linkage_mismatches", sum(1 for item in matches + provisional_matches if item["original"].llvm_linkage != item["adamas"].llvm_linkage)),
    ]
    for tier, count in sorted(collections.Counter(item["candidate"].tier for item in matches).items()):
        summary_rows.append((f"match_tier.{tier}", count))
    for state, count in sorted(summary["body_states"].items()):
        summary_rows.append((f"body_state.{state}", count))
    for side, counts in (("original", original_summary["categories"]), ("adamas", adamas_summary["categories"])):
        for category, count in sorted(counts.items()):
            summary_rows.append((f"{side}.category.{category}", count))
    for family in adamas_families:
        summary_rows.append((f"adamas.family.{family['category']}.{family['family']}", family["count"]))
    for family in summary["top"]["adamas_only_families"]:
        summary_rows.append((f"adamas_only.family.{family['category']}.{family['family']}", family["count"]))
    write_tsv(out_dir / "summary.tsv", ["metric", "value"], summary_rows)
    print(json.dumps({"matches": len(matches), "original_only": len(original_only), "adamas_only": len(adamas_only), "out_dir": str(out_dir)}, sort_keys=True))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--original-ll", required=True, help="original Crystal LLVM IR")
    parser.add_argument("--adamas-ll", required=True, help="Adamas LLVM IR")
    parser.add_argument("--out-dir", required=True, help="directory for deterministic reports")
    parser.add_argument("--top", type=int, default=20, help="number of top owner/method rows (default: 20)")
    return parser


def main(argv: Optional[list[str]] = None) -> int:
    try:
        args = build_parser().parse_args(argv)
        return run(args)
    except InputError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    except (OSError, ValueError, UnicodeError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
