# Third-Party Notices

Tab-List 1.0 directly links one runtime dependency:

## Sparkle 2.9.4

Sparkle is an open-source software update framework for macOS.

- Project: <https://github.com/sparkle-project/Sparkle>
- Version: 2.9.4
- License: MIT-style license with additional notices for bundled components
- Complete authoritative license: [`Resources/Legal/Sparkle-LICENSE.txt`](Resources/Legal/Sparkle-LICENSE.txt), copied from <https://github.com/sparkle-project/Sparkle/blob/2.9.4/LICENSE>

Copyright © 2006–2013 Andy Matuschak; © 2009–2013 Elgato Systems GmbH; © 2011–2014 Kornel Lesiński; © 2015–2017 Mayur Pawashe; © 2014 C.W. Betts, Petroules Corporation, and Big Nerd Ranch.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

Sparkle’s license also carries notices for bsdiff/bspatch, sais-lite, an Ed25519 implementation, and `SUSignatureVerifier.m`. The unmodified complete `LICENSE` copied under `Resources/Legal` is the controlling notice. Release automation verifies that it is bundled in the application and included in the DMG’s `Documentation` folder.

## Build tooling

[XcodeGen](https://github.com/yonaskolb/XcodeGen) is an MIT-licensed development tool used to generate the Xcode project. It is not linked into or distributed with the Tab-List application.

Apple SDK frameworks are supplied by the operating system and Xcode under Apple’s applicable license terms.

No AltTab source code, assets, or other GPL-licensed implementation material is included in Tab-List.
