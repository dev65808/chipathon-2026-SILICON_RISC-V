// Minimal stand-in for Makerchip's internal `pseudo_rand` module.
// Not part of the  actual core logic — Makerchip auto-inserts a real instance
// of this for some internal library randomization features, but doesn't
// export its definition into top.sv/top_gen.sv. This stub just satisfies the
// module reference so the design elaborates; its output isn't consumed by
// any of the core's actual decode/ALU/register logic.

module pseudo_rand #(parameter WIDTH = 1) (
    input  wire clk,
    input  wire reset,
    output reg  [WIDTH-1:0] out
);
    always @(posedge clk) begin
        if (reset)
            out <= {WIDTH{1'b0}};
        else
            out <= out + 1'b1;
    end
endmodule
