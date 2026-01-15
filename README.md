# Blinkyy

Blinkyy is the culmination of a weeks-long effort to be able to install Rust firmware for the Arduino Uno R3 from a remote source using Nix. It is your run of the mill LED blink program, but with superpowers.

## Try with Nix

If you have Nix installed with flakes enabled, you can install this with a single command. Plug in your board, and run 

```nix
nix run 'github:of-the-stars/blinkyy'
```

This will flash the firmware to your board and make its LED flash every 10 seconds.


## License
Licensed under either of

 - Apache License, Version 2.0
   ([LICENSE-APACHE](LICENSE-APACHE) or <http://www.apache.org/licenses/LICENSE-2.0>)
 - MIT license
   ([LICENSE-MIT](LICENSE-MIT) or <http://opensource.org/licenses/MIT>)

at your option.

## Contribution
Unless you explicitly state otherwise, any contribution intentionally submitted
for inclusion in the work by you, as defined in the Apache-2.0 license, shall
be dual licensed as above, without any additional terms or conditions.
