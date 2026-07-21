# Chipathon 2026 Team A30 SILICON_RISC-V 

- **TITLE**: 32-bit RISC-V (RV32I) microcontroller using TL-Verilog and Librelane-ORFS Flow
- **DESCRIPTION**:The project aims to design and implement a basic **32-bit RISC-V processor** compliant with the RV32I base instruction set. Two prime objective of this project:
  - **TL-Verilog (TLV)** from [Redwood EDA](https://redwoodeda.com) will be used to develop the RISC-V core. TLV's transaction-level modeling and timing abstraction will enable for faster development and better architectural insight. The [MakeChip IDE](https://makerchip.com) overs interactive documentation and a very powerful visualization code that makes design and verification of the designs like RISC-V processor very efficient. We believe this is the first time TLV is used Chipathon. A design methodology involving TLV will be good value addition to the open-source ecosystem.
  - **QSPI Flash and RAM as Reusable IP**: When designing small RISC-V cores, adding SRAM for instruction and data is usually not practical. Instead, accessing an extrnal FLASH and RAM through a QSPI protocol is a great choice is speed is not an issue. Although there are few RISCV in the open-source community, they are embedded in designs which makes it diffcult for designers to drop it in their design as an _reusable IP_. The aim of this project is to create such an resuable IP.
  - **UART and SPI as Reusable IP**: UART and SPI allows a RISCV core to interact with external world and create a tiny microcontroller-type device. The UART can be used to interact with a terminla and SPI display can be used as the monitor.
---
- [Original README for this repo template](docs/repo-README.md)
---
## License

Apache-2.0, inherited from upstream. See `LICENSE` for the full text,
`NOTICE` for attribution of third-party material, and `AUTHORS.md`
for the list of copyright holders.
