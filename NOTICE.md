# Notice

This project is a Nimony port of an upstream open-source Rust Minecraft
server implementation. Porting means translating that project's source,
module by module, into Nimony while following its structure and logic —
this is a derivative work, not an independent implementation.

The upstream project is licensed under the **GNU General Public License
v3.0 (GPLv3)**. As a derivative work, this project is licensed under the
same terms — see `LICENSE` in this repository for the full text. In
particular, per the GPLv3:

- This project may be used, modified, and redistributed, but any
  distributed copy or derivative must remain under GPLv3 and retain
  copyright/license notices.
- Source availability must be preserved for anyone who receives a binary
  built from this code.

A local clone of the upstream source is kept alongside this repository
(as a sibling directory, not vendored in) purely as a porting reference;
each ported `.nim` file's doc comment names the specific upstream source
file it was translated from, for traceability.
