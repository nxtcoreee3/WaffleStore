# Attribution and redistribution status

The SAP v200 protocol/state flow in `MapleSyrup/SAPKit` is adapted from
[majd/ipatool](https://github.com/majd/ipatool), pinned at
`3411d57f451f5111ae115641c22f7ed17bbd5fbe` (2026-10-01).
The adaptation uses Swift protocol code and a statically linked guest-only
Go library, not an embedded ipatool executable. Experimental Unicorn/TCI is
statically linked in the IPA. Apple proprietary assets are **not** bundled;
the guest downloads hash-pinned assets into the app's cache when requested.
The Linux negative test downloads upstream Unicorn separately via pip.

## ipatool MIT notice

MIT License

Copyright (c) 2021 Majd Alfhaily

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## WaffleStore and future runtime work

At the original revision `d508e532e5b40d6470bab003a6cc0026d1ca7c75`, the
WaffleStore tree has no LICENSE/COPYING file granting redistribution rights.
Public source visibility alone is not an MIT license. Existing Mineek,
PancakeStore, jailbreak.party, Skadz and nxtcoreee3 attributions are retained.
Public redistribution of a modified binary needs clarification from the
relevant upstream rightsholders; this work does not grant those rights.
CI creates **draft** prereleases for development tags, not public releases.

The existing SwiftPM dependencies retain their upstream notices. See the pinned
`Package.resolved` for PartyUI, Zip, Telegraph, CocoaAsyncSocket and HTTPParserC.
Unicorn includes GPL-2.0 code; ipatool's MIT license does not relicense Unicorn.
The restored QEMU TCI sources preserve their GPL headers. Every CI artifact
includes the modified corresponding source for Unicorn/TCI, its COPYING file,
and the source/notice for the guest bridge. The embedded Go dependencies retain
their licenses (including purego Apache-2.0); the build generates their complete
notices from the dependency modules. The combined licensing and upstream
redistribution rights require review before public binary publication; providing
source alone does not resolve an incompatible combination or missing upstream
grant. Apple CommerceKit/CoreFP/StoreAgent binaries have their
own proprietary terms; downloading them from Apple does not grant a right to
bundle them in a redistributed IPA. No such binaries have been copied here.
