## Team Members
- Gokilavani Chinnasamy, _PhD Student, SUNY Buffalo_
- Dev Jyoti, _Graduated, ECE, Silicon University (Lead)_

## Description
The project aims to design and implement a basic 32-bit RISC-V processor compliant with the RV32I base instruction set. Two prime objective of this project:
- **TL-Verilog (TLV)** from Redwood EDA will be used to develop the RISC-V core. TLV's transaction-level modeling and timing abstraction will enable for faster development and better architectural insight. The MakeChip IDE overs interactive documentation and a very powerful visualization code that makes design and verification of the designs like RISC-V processor very efficient. We believe this is the first time TLV is used Chipathon. A design methodology involving TLV will be good value addition to the open-source ecosystem.
- **QSPI Flash and RAM as Reusable IP**: When designing small RISC-V cores, adding SRAM for instruction and data is usually not practical. Instead, accessing an extrnal FLASH and RAM through a QSPI protocol is a great choice is speed is not an issue. Although there are few RISCV in the open-source community, they are embedded in designs which makes it diffcult for designers to drop it in their design as an reusable IP. The aim of this project is to create such an resuable IP.
- **UART and SPI as Reusable IP**: UART and SPI allows a RISCV core to interact with external world and create a tiny microcontroller-type device. The UART can be used to interact with a terminla and SPI display can be used as the monitor.

## Resources
- [GitHub Repo link](https://github.com/dev65808/chipathon-2026-SILICON_RISC-V/tree/main)
- [Project Tracker](https://docs.google.com/spreadsheets/d/1wQm1r5oKgr6FuifQ1QYUZetHXA55ssTZTbZV7EYZYDo/edit?gid=0#gid=0)
- [Schematic Review-I](https://docs.google.com/presentation/d/1GLPuPCLZmV2Rm8AvjZc3W22Fm0hJxebE1r7IQ_BO_P0/edit?slide=id.p#slide=id.p) ( [Video Presentation](https://drive.google.com/file/d/1z7d04HLMgYPdQ1I4gIQjpsTB3c4_ydIF/view?usp=sharing) )
- [Original Proposal Link](https://docs.google.com/presentation/d/1rSuEfeSLhpgLdwgq0cfRaWU_6pLCKb8bpQmk9ejvyKY/edit?slide=id.g3eb6fba5153_0_0#slide=id.g3eb6fba5153_0_0)



