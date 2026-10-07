# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

## Stack

Delegated: native macOS AppKit and WebKit, with Swift 6 and the existing HTML, CSS, and JavaScript mockup as the interface source.

## Users

Luis uses WhatsApp on a Mac and has a large personal sticker library. He wants to find stickers by meaning and keep useful groups in WhatsApp without manually sorting each new sticker.

## Product Purpose

Stickr reads the local WhatsApp sticker library, describes each sticker through an OpenAI-compatible model, searches it in German and English, builds rule-based packs, and imports those packs through WhatsApp's official sticker pack flow.

## Positioning

A pack is one saved meaning search plus explicit pins and removals. Search and pack membership use the same vectors and ranking.

## Operating Context

Stickr is a low-resource macOS menu-bar app. Normal sending remains inside WhatsApp. A command-line interface exposes the same library, model, search, pack, and install operations for testing and automation.

## Capabilities and Constraints

- Read copies of WhatsApp databases and copy sticker files into Stickr storage. Never write to WhatsApp files.
- Use `z-ai/glm-5.3-flash` and `baai/bge-m3` by default through OpenRouter. Support another OpenAI-compatible base URL.
- Keep API credentials in the macOS Keychain.
- Build packs of at most 30 members. Split still and animated stickers.
- Import through WhatsApp's official third-party sticker-pack pasteboard type and URL.
- Use no Electron, React, local model, vector database, or background daemon.
- Ship as a signed and notarized DMG. Run with no Dock icon.
- Test WhatsApp actions only in the chat named `Notizen`.

## Brand Commitments

The product name is Stickr. The approved visual and copy source is `mockup/walkthrough.html`, `mockup/walkthrough.css`, and `mockup/walkthrough.js`. It uses the system font, WhatsApp green, one radius scale, plain sentences, and light and dark appearance.

## Evidence on Hand

- The walkthrough contains every required screen and state.
- `mockup/stickers/` contains 40 test stickers.
- `tests/search_cases.json` contains measured German and English search cases.
- The local WhatsApp library and installed test packs provide real integration evidence but are never committed.

## Product Principles

- Keep sending in WhatsApp.
- Make model behavior visible and editable.
- Keep automatic work quiet, cheap, and recoverable.
- Use one meaning system for search and packs.
- State failures in plain language and preserve usable local results.

## Accessibility & Inclusion

Support keyboard operation, visible focus, VoiceOver labels, system light and dark appearance, and reduced motion. Accessibility permission for WhatsApp cleanup stays optional.
