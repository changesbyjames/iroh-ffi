# `@strangecyan/iroh`

> A toolkit for building distributed applications

A fork of [`@number0/iroh`](https://www.npmjs.com/package/@number0/iroh), from
[changesbyjames/iroh-ffi](https://github.com/changesbyjames/iroh-ffi/tree/relayed-connections), built on
[an iroh fork](https://github.com/changesbyjames/iroh/tree/relayed-connections). It adds
`Incoming.acceptWithoutNatTraversal()`: the connection never negotiates holepunching, so the endpoint does not reveal
its IP addresses to that remote, and the connection stays on the relay it arrived through. Everything else is
upstream's. Versions are upstream's with a `-relayed.N` suffix.

## Install

```sh
> npm i --save @strangecyan/iroh
```

To keep imports of `@number0/iroh` working, alias it, for example with a pnpm override:
`'@number0/iroh': npm:@strangecyan/iroh@1.1.0-relayed.1`.


## Development

```sh
# debug build
> yarn build:debug

# run tests
> yarn test
```


## License

This project is licensed under either of

 * Apache License, Version 2.0, ([LICENSE-APACHE](LICENSE-APACHE) or
   http://www.apache.org/licenses/LICENSE-2.0)
 * MIT license ([LICENSE-MIT](LICENSE-MIT) or
   http://opensource.org/licenses/MIT)

at your option.

### Contribution

Unless you explicitly state otherwise, any contribution intentionally submitted
for inclusion in this project by you, as defined in the Apache-2.0 license,
shall be dual licensed as above, without any additional terms or conditions.
