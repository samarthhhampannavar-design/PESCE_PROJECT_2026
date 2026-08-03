module top(
	input clk,
	input rst,
	input [31:0] instruction,
	output [7:0] pc,

	// ---- Data memory interface (externalized) ----
	// The "memory" module is not instantiated inside "top".
	// Wire these ports up to your own externally instantiated
	// memory / SRAM / BRAM module in your testbench / wrapper module.
	output        mem_write,
	output [7:0]  mem_addr,
	output [7:0]  mem_write_data,
	input  [7:0]  mem_read_data
	);


//--------------------------------------WIRES-----------------------
//global wires
wire wire_clk,wire_rst;

//control unit wires
wire [31:0]wire_instruction;
wire [3:0]wire_alu_sel;
wire wire_memwrite,wire_regwrite,wire_immsel,wire_wbsel;
wire [2:0] wire_imm_type;
wire wire_regsel;


//alu wire
wire [7:0]wire_a2,wire_alu_out;
wire wire_branch;

//reg bank wire
wire [7:0]wire_Drs1,wire_Drs2,wire_Drd;
wire [4:0] wire_Ars1,wire_Ars2,wire_Ard;

assign wire_Ars1=wire_instruction[19:15];
assign wire_Ars2=wire_instruction[24:20];
assign wire_Ard=wire_instruction[11:7];

//immediate generator wire
wire [7:0]wire_imm_out;

//pc and instruction memory wire
wire [7:0]wire_pc_in,wire_pc_out,wire_pc_plus_out;

//mux21 wires
wire [7:0]wire_wb_out;

//ADDER wire
wire [7:0]wire_add_out;

//mux41 wires
wire wire_pcsel;
wire wire_jal_sel,wire_or_out;

//---------------------INTERMEDIATE LOGIC------------------------
wire and_regwrite_out,and_memwrite_out;

assign wire_clk=clk;
assign wire_rst=rst;
assign and_regwrite_out=wire_regwrite&wire_rst;
assign and_memwrite_out=wire_memwrite&wire_rst;
assign wire_or_out=wire_jal_sel | wire_branch;

//----------------MATRIX-MULTIPLY EXTENSION WIRES----------------
// New custom opcodes, decoded by control_unit:
//   MAT_LD  = 7'b0001011  -> load matrix A or matrix B from data memory
//   MAT_MUL = 7'b0101011  -> kick off the 2x2 signed matrix multiply
//   MAT_ST  = 7'b1011011  -> store C[0][0]..C[1][1] back to data memory
wire wire_mat_ld, wire_mat_mul, wire_mat_st;
// funct3 bit0 of a MAT_LD instruction selects the load target:
//   0 = matrix A (a_flat), 1 = matrix B (b_flat)
wire wire_mat_ld_sel = wire_instruction[12];

wire        mat_busy;        // 1 while a MAT_* multi-cycle sequence is in flight
wire        mat_ovr_active;  // 1 -> matrix_ctrl owns the data-memory bus this cycle
wire [7:0]  mat_ovr_addr;
wire [7:0]  mat_ovr_wdata;
wire        mat_ovr_write;

wire [31:0] mat_a_flat, mat_b_flat;
wire        mat_mm_write_mem, mat_mm_start, mat_mm_done;
/* verilator lint_off UNUSEDSIGNAL */
wire signed [16:0] mat_c_out_0_0, mat_c_out_0_1, mat_c_out_1_0, mat_c_out_1_1;
/* verilator lint_on UNUSEDSIGNAL */


//------------------OUTPUT FOR TOPMODULE---------------------
assign pc=wire_pc_out;

//------------------INPUT FROM TOPMODULE (instruction memory brought out)------
assign wire_instruction=instruction;

//------------------DATA MEMORY INTERFACE DRIVES (memory brought out)---------
// While matrix_ctrl is streaming matrix A/B in or matrix C back out
// (mat_ovr_active), it owns mem_addr/mem_write/mem_write_data
// outright; otherwise the bus behaves exactly as before.
assign mem_write      = mat_ovr_active ? mat_ovr_write : and_memwrite_out;
assign mem_addr       = mat_ovr_active ? mat_ovr_addr  : wire_alu_out;
assign mem_write_data = mat_ovr_active ? mat_ovr_wdata : wire_Drs2;
// mem_read_data is driven from outside "top" and used directly below
// wherever the old internal "wire_read_data" was used.

//-----------------------INSTANCES---------------------------------

//control unit instance
control_unit p1(.opcode(wire_instruction[6:0]),
	.fn3(wire_instruction[14:12]),
	.fn7(wire_instruction[31:25]),
	.alu_sel(wire_alu_sel),
	.memwrite(wire_memwrite),
	.regwrite(wire_regwrite),
	.pc_sel(wire_pcsel),
	.imm_sel(wire_immsel),
	.wb_sel(wire_wbsel),
	.reg_sel(wire_regsel),
	.imm_type(wire_imm_type),
	.jal_sel(wire_jal_sel),
	.mat_ld(wire_mat_ld),
	.mat_mul(wire_mat_mul),
	.mat_st(wire_mat_st)
	);

//alu instance
alu p2(.a1(wire_Drs1),
	.a2(wire_a2),
	.sel(wire_alu_sel),
	.alu_out(wire_alu_out),
	.branch(wire_branch)
	);

//register bank instance
reg_bank p3(.i_clk(wire_clk),
	.i_rst(wire_rst),
	.i_write_enable(and_regwrite_out),
	.i_rs1(wire_Ars1),
	.i_rs2(wire_Ars2),
	.i_rd(wire_Ard),
	.i_drd(wire_Drd),
	.o_drs1(wire_Drs1),
	.o_drs2(wire_Drs2)
	);
//Immediate generator instnce
immediate_generator p4(.i_instruction(wire_instruction[31:7]),
	.s(wire_imm_type),
	.imm_out(wire_imm_out)
	);

// Instruction memory is instantiated OUTSIDE top and connected via
// the top-level pins: pc (output of top) -> instruction memory's
// address input, and instruction memory's data output -> instruction
// (input of top).

pc p7(.clk(wire_clk),
	.rst(wire_rst),
	.pc_in(wire_pc_in),
	.hold(mat_busy),
	.pc_out(wire_pc_out),
	.pc_plus_out(wire_pc_plus_out)
	);


//mux instances
mux imm(.i0(wire_Drs2),
	.i1(wire_imm_out),
	.sel(wire_immsel),
	.out(wire_a2)
	);

mux wb(.i0(wire_alu_out),
	.i1(mem_read_data),
	.sel(wire_wbsel),
	.out(wire_wb_out)
	);

mux41 pc_mux(.in0(wire_pc_plus_out),
	.in1(wire_alu_out),
	.in2(wire_add_out),
	.in3(8'b0),
	.sel({wire_or_out,wire_pcsel}),
	.out(wire_pc_in)
	);

// reg_sel=0 -> normal ALU/load-data writeback, reg_sel=1 -> link register (JAL/JALR)
mux regw(.i0(wire_wb_out),
	.i1(wire_pc_plus_out),
	.sel(wire_regsel),
	.out(wire_Drd)
	);

adder ad(.a(wire_imm_out),
	.b(wire_pc_out),
	.y(wire_add_out)
	);

//---------------- MATRIX-MULTIPLY EXTENSION INSTANCES ----------------
// matrix_ctrl runs the multi-cycle MAT_LD / MAT_MUL / MAT_ST sequences,
// stealing the data-memory bus and freezing the PC (via mat_busy) for as
// long as each sequence takes.
matrix_ctrl u_matrix_ctrl(
	.clk         (wire_clk),
	.rst_n       (wire_rst),
	.mat_ld      (wire_mat_ld),
	.mat_mul     (wire_mat_mul),
	.mat_st      (wire_mat_st),
	.mat_ld_sel  (wire_mat_ld_sel),
	.base_addr   (wire_alu_out),      // rs1 + imm, computed by the existing ALU
	.mem_read_data(mem_read_data),
	.c_out_0_0   (mat_c_out_0_0[15:0]),
	.c_out_0_1   (mat_c_out_0_1[15:0]),
	.c_out_1_0   (mat_c_out_1_0[15:0]),
	.c_out_1_1   (mat_c_out_1_1[15:0]),
	.mm_done     (mat_mm_done),

	.busy        (mat_busy),
	.ovr_active  (mat_ovr_active),
	.ovr_mem_addr (mat_ovr_addr),
	.ovr_mem_wdata(mat_ovr_wdata),
	.ovr_mem_write(mat_ovr_write),

	.a_flat      (mat_a_flat),
	.b_flat      (mat_b_flat),
	.mm_write_mem(mat_mm_write_mem),
	.mm_start    (mat_mm_start)
	);

matrix_multiplier_2x2 u_matrix_multiplier_2x2(
	.clk       (wire_clk),
	.rst_n     (wire_rst),
	.a_flat    (mat_a_flat),
	.b_flat    (mat_b_flat),
	.start     (mat_mm_start),
	.write_mem (mat_mm_write_mem),
	.c_out_0_0 (mat_c_out_0_0),
	.c_out_0_1 (mat_c_out_0_1),
	.c_out_1_0 (mat_c_out_1_0),
	.c_out_1_1 (mat_c_out_1_1),
	.done      (mat_mm_done)
	);

endmodule


module alu(
    input [7:0] a1,
    input [7:0] a2,
    input [3:0] sel,
    output reg branch,
    output reg [7:0] alu_out
);

always @(*) begin
    case(sel)
        0: begin
            alu_out = a1 + a2;
            branch = 0;
        end
        1: begin
            if(a1 >= a2)
                alu_out = a1 - a2;
            else
                alu_out = a2 - a1;
            branch = 0;
        end
        2: begin
            alu_out = a1 ^ a2;
            branch = 0;
        end
        3: begin
            alu_out = a1 | a2;
            branch = 0;
        end
        4: begin
            alu_out = a1 & a2;
            branch = 0;
        end
        5: begin
            alu_out = a1 << a2[4:0];
            branch = 0;
        end
        6: begin
            alu_out = a1 >> a2[4:0];
            branch = 0;
        end
        7: begin
            alu_out = $signed(a1) >>> a2[4:0];
            branch = 0;
        end
        8: begin
            alu_out = ($signed(a1) < $signed(a2)) ? 8'd1 : 8'd0;
            branch = 0;
        end
        9: begin
            alu_out = (a1 < a2) ? 8'd1 : 8'd0;
            branch = 0;
        end

        // Branch comparisons
        10: begin // BEQ
            branch = (a1 == a2);
            alu_out = 0;
        end
        11: begin // BNE
            branch = (a1 != a2);
            alu_out = 0;
        end
        12: begin // BLTU
            branch = (a1 < a2);
            alu_out = 0;
        end
        13: begin // BGEU
            branch = (a1 >= a2);
            alu_out = 0;
        end
        14: begin // BLT
            branch = ($signed(a1) < $signed(a2));
            alu_out = 0;
        end
        15: begin // BGE
            branch = ($signed(a1) >= $signed(a2));
            alu_out = 0;
        end

        default: begin
            alu_out = 0;
            branch = 0;
        end
    endcase
end

endmodule


module control_unit(
	input 	    [6:0] opcode,
	input       [2:0] fn3,
	input 	    [6:0] fn7,
	output reg  [3:0] alu_sel,
	output reg        memwrite,
	output reg        regwrite,
	output reg        pc_sel,
	output reg        imm_sel,
	output reg        wb_sel,
	output reg        reg_sel,
	output reg  [2:0] imm_type,
	output reg	  jal_sel,
	output reg	  mat_ld,   // MAT_LD  (0001011): load matrix A or B from memory
	output reg	  mat_mul,  // MAT_MUL (0101011): start the 2x2 matrix multiply
	output reg	  mat_st    // MAT_ST  (1011011): store C back out to memory
	);

// NOTE: several branches below (e.g. fn3=3'h0 / 3'h5 under R-TYPE and
// I-TYPE <ALU>) only assign alu_sel for specific fn7 values with no
// else/default, so alu_sel intentionally retains its previous value
// otherwise. This always block therefore models a latch and is written
// as always_latch rather than always@(*).
always @(*) begin
	imm_type = 3'd0;
	regwrite = 1'b0;
	memwrite = 1'b0;
	pc_sel   = 1'b0;
	imm_sel  = 1'b0;
	wb_sel   = 1'b0;
	reg_sel  = 1'b0;
	jal_sel  = 1'b0;
	alu_sel  = 4'd0;
	mat_ld   = 1'b0;
	mat_mul  = 1'b0;
	mat_st   = 1'b0;

	case(opcode)
		7'b0110011:begin		//R TYPE
			imm_type=0;
			regwrite=1;
			memwrite=0;
			pc_sel=0;
			imm_sel=0;
			wb_sel=0;
			reg_sel=0;
			jal_sel=0;
			case(fn3)
				3'h0:begin
					if(fn7==0)begin
					        alu_sel=0;	//ADD
				        end
				        else if(fn7==7'h20)begin
					        alu_sel=1;	//SUB
					end
				end
				3'h4:begin
					alu_sel=2;		//XOR
				end
				3'h6:begin
					alu_sel=3;		//OR
				end
			        3'h7:begin
					alu_sel=4;		//AND
				end	
				3'h1:begin
					alu_sel=5;		//SHIFT LEFT LOGICAL
				end
				3'h5:begin
					if(fn7==0)begin
						alu_sel=6;	//SHIFT RIGHT LOGICAL
					end
					else if(fn7==7'h20)begin
						alu_sel=7;	//SHIFT RIGHT ARITHMETIC
					end
				end
				3'h2:begin
					alu_sel=8;		//SET LESS THAN
				end
				3'h3:begin
					alu_sel=9;		//SET LESS THAN (U)
				end
				default:alu_sel=0;
			endcase
		end
		7'b0010011:begin	//I TYPE <ALU> 
			imm_type=0;
			regwrite=1;
			memwrite=0;
			pc_sel=0;
			imm_sel=1;
			wb_sel=0;
			reg_sel=0;
			jal_sel=0;
			case(fn3)
				3'h0:alu_sel=0;
				3'h4:alu_sel=2;
				3'h6:alu_sel=3;
				3'h7:alu_sel=4;
				3'h1:alu_sel=5;
				3'h5:begin
					if(fn7==7'h00)begin
						alu_sel=6;	//SHIFT RIGHT LOGICAL
					end
					else if(fn7==7'h20)begin
						alu_sel=7;
					end
				end
				3'h2:alu_sel=8;
				3'h3:alu_sel=9;
				default:alu_sel=0;
			endcase
		end
		7'b0000011:begin	//I TYPE <LOAD>
			imm_type=0;
			regwrite=1;
			memwrite=0;
			pc_sel=0;
			imm_sel=1;
			wb_sel=1;
			reg_sel=0;
			alu_sel=0;
			jal_sel=0;
		end
		7'b0100011:begin	//S TYPE
			imm_type=1;
			regwrite=0;
			memwrite=1;
			pc_sel=0;
			imm_sel=1;
			wb_sel=0;
			reg_sel=0;
			alu_sel=0;
			jal_sel=0;
		end
		7'b1100111:begin	//I TYPE <JALR>
			imm_type=0;
			regwrite=1;
			memwrite=0;
			pc_sel=1;
			imm_sel=1;
			wb_sel=0;
			reg_sel=1;
			alu_sel=0;
			jal_sel=0;
		end
		7'b1100011:begin     //BRANCH (B) type instructions
			imm_type=2;
			regwrite=0;
			memwrite=0;
			pc_sel=1'b0;
			imm_sel=0;
			wb_sel=0;
			reg_sel=0;
			jal_sel=0;
			case(fn3)
				3'h0:alu_sel=10;
				3'h1:alu_sel=11;
				3'h4:alu_sel=12;
				3'h5:alu_sel=13;
				3'h6:alu_sel=14;
				3'h7:alu_sel=15;
				default:alu_sel=10;
			endcase
		end
		// NOTE: 7'b0110111 (LUI) and 7'b0010111 (AUIPC) removed.
		// Both used imm_type=3 (u_type), whose immediate is now always
		// 8'b0 at 8-bit operand width (see immediate_generator), which
		// made LUI always write 0 and AUIPC always resolve to "reg=pc".
		// Unhandled opcodes now simply fall through to the default case.
		7'b1101111:begin     //JUMP (J) type instructions
			imm_type=4;
			regwrite=1;
			memwrite=0;
			pc_sel=0;
			imm_sel=0;
			wb_sel=0;
			reg_sel=1;
			alu_sel=0;
			jal_sel=1;
		end
		7'b0001011:begin    //MAT_LD (custom-0): load matrix A or matrix B from memory
			// Same address computation as a normal I-type load: base = rs1 + imm.
			// matrix_ctrl does the actual 4-byte-burst read and register capture;
			// this opcode does NOT write the register file or issue a normal
			// memory access itself (regwrite=0, memwrite=0).
			imm_type=0;      // i_type immediate, imm[7:0] = instruction[27:20]
			regwrite=0;
			memwrite=0;
			pc_sel=0;
			imm_sel=1;       // ALU computes rs1 + imm
			wb_sel=0;
			reg_sel=0;
			alu_sel=0;       // ADD -> base address
			jal_sel=0;
			mat_ld=1'b1;
		end
		7'b0101011:begin    //MAT_MUL (custom-1): start the 2x2 signed matrix multiply
			// No operands are consumed from the instruction; matrix_ctrl simply
			// pulses "start" into matrix_multiplier_2x2 and holds the PC until
			// the multiplier's "done" pulse arrives (9 cycles later).
			imm_type=0;
			regwrite=0;
			memwrite=0;
			pc_sel=0;
			imm_sel=0;
			wb_sel=0;
			reg_sel=0;
			alu_sel=0;
			jal_sel=0;
			mat_mul=1'b1;
		end
		7'b1011011:begin    //MAT_ST (custom-2): store C[0][0]..C[1][1] back to memory
			// Same address computation as a normal S-type store: base = rs1 + imm.
			// matrix_ctrl streams all 4 c_out registers (2 bytes each, low byte
			// first) out to consecutive addresses starting at base, one byte per
			// clock, and holds the PC until the whole burst is written.
			imm_type=1;      // s_type immediate, matches a normal store's encoding
			regwrite=0;
			memwrite=0;
			pc_sel=0;
			imm_sel=1;       // ALU computes rs1 + imm
			wb_sel=0;
			reg_sel=0;
			alu_sel=0;       // ADD -> base address
			jal_sel=0;
			mat_st=1'b1;
		end
		default:begin          //for any other type of opcode(except R,I,S,B,J,U), the operation should be --- R type-> ADDition Operation
			imm_type=0;
			regwrite=1;
			memwrite=0;
			pc_sel=0;
			imm_sel=0;
			wb_sel=0;
			reg_sel=0;
			alu_sel=0;
			jal_sel=0;
		end
	endcase
end
endmodule


module immediate_generator(
	/* verilator lint_off UNUSEDSIGNAL */
	input [31:7]i_instruction,
	/* verilator lint_on UNUSEDSIGNAL */
	input [2:0]s,
	output reg [7:0] imm_out
);
parameter i_type=3'd0;
parameter s_type=3'd1;
parameter b_type=3'd2;
parameter j_type=3'd4;
// NOTE: u_type (imm_type=3, previously used by LUI/AUIPC) removed.
// At 8-bit operand width its low-byte-truncated immediate was always
// 8'b0, so both instructions that used it were dropped from control_unit.
always@(*) begin
	case(s)
		i_type:imm_out=i_instruction[27:20];
		s_type:imm_out={i_instruction[27:25],i_instruction[11:7]};
		b_type:imm_out={i_instruction[27:25],i_instruction[11:8],1'b0};
		j_type:imm_out={i_instruction[27:21],1'b0};
		default: imm_out=0;
	endcase
end
endmodule

module mux(
	input [7:0]i0,
	input [7:0]i1,
	input sel,
	output [7:0]out
	);
assign out=sel?i1:i0;
endmodule

module mux41(
	input [7:0] in0,
	input [7:0] in1,
	input [7:0] in2,
	input [7:0] in3,
	input [1:0] sel,
	output reg [7:0] out
	);
always@(*) begin
	//out=0;
	case(sel)
		0: out=in0;
		1: out=in1;
		2: out=in2;
		3: out=in3;
		default: out=0;
	endcase
end
endmodule

module pc(

input clk,
input rst,
input [7:0]pc_in,
input hold,        // 1 -> PC freezes at its current value this cycle (matrix ops)
output [7:0] pc_out,
output [7:0] pc_plus_out

);

reg [7:0]pc;
always @(posedge clk or negedge rst)
begin

      if(!rst)begin
      pc <= 0; 
      end

      else if(!hold) begin
      pc <= pc_in;
      end
      // else: hold==1, pc keeps its current value (frozen during a MAT_* burst)
end
assign pc_plus_out=pc+4;
assign pc_out=pc;

endmodule
module reg_bank(
	input i_clk,
	input i_rst,
	input i_write_enable, //write enable
	input [4:0]i_rs1, //address of 1st source register
	input [4:0]i_rs2, //address of 2nd source register
	input [4:0]i_rd, //address of destination register
	input [7:0]i_drd, // data to be write at address of destination register 
	output [7:0]o_drs1, // data of source register 1 
	output [7:0]o_drs2 //  data of source register 2
);
reg [7:0] register [0:31];

always@(posedge i_clk or negedge i_rst) begin
	if(!i_rst) begin
		for(integer i=0;i<32;i=i+1) begin
			register[i]<=0;
		end
		//o_drs1<=0;
		//o_drs2<=0;
	end
	else begin
		if(i_write_enable && i_rd != 5'd0) begin
			register[i_rd]<=i_drd;
		end
		register[0]<=8'd0;
	end
end
assign o_drs1=register[i_rs1];
assign o_drs2=register[i_rs2];

endmodule

module adder(
	input [7:0]a,b,
	output [7:0]y
	);
	assign y=a+b;
endmodule


// ============================================================================
// matrix_ctrl : multi-cycle controller for the three new matrix opcodes.
//
// This module is the only piece of "top" that talks to the data-memory bus
// while a matrix operation is in flight (mat_ovr_active) and it is the only
// thing that asserts "busy" (which freezes the PC via pc.hold). Everything
// else in "top" -- the ALU, the normal load/store path, the register file --
// keeps working exactly as it always did whenever busy==0.
//
// MAT_LD  (opcode 0001011, decoded as mat_ld):
//   Reads 4 consecutive bytes from memory, starting at base_addr = rs1+imm,
//   least-significant byte first, and assembles them into a 32-bit word.
//   funct3 bit0 (mat_ld_sel) chooses the destination:
//     mat_ld_sel==0 -> a_flat  (matrix A)
//     mat_ld_sel==1 -> b_flat  (matrix B)
//   Software loads matrix A with one MAT_LD, then matrix B with another.
//   Takes 5 cycles (4 reads + 1 latch cycle); PC is held throughout.
//
// MAT_MUL (opcode 0101011, decoded as mat_mul):
//   Pulses "start" into matrix_multiplier_2x2 and waits for its "done"
//   pulse (9 cycles later per the multiplier's own pipeline latency).
//   PC is held for the whole 10-cycle sequence.
//
// MAT_ST  (opcode 1011011, decoded as mat_st):
//   Writes all 4 C[i][j] results back to memory, 2 bytes each (low byte
//   then high byte -- each c_out_i_j is 17 bits; bit 16, the rare overflow
//   bit, is dropped since this is an 8-bit-datapath machine), one byte per
//   clock, to consecutive addresses starting at base_addr = rs1+imm, in the
//   order C[0][0], C[0][1], C[1][0], C[1][1]. Takes 8 cycles; PC is held
//   throughout so no instruction can slip in mid-burst.
// ============================================================================
module matrix_ctrl (
	input        clk,
	input        rst_n,          // active-low reset (same convention as the rest of "top")

	// opcode strobes, decoded combinationally by control_unit from the
	// instruction currently sitting at the (frozen, while busy) PC
	input        mat_ld,
	input        mat_mul,
	input        mat_st,
	input        mat_ld_sel,     // funct3[0]: 0 = target A, 1 = target B

	input  [7:0] base_addr,      // rs1 + imm, from the existing ALU/adder path

	input  [7:0] mem_read_data,  // external data memory, combinational read

	input  signed [15:0] c_out_0_0, c_out_0_1, c_out_1_0, c_out_1_1,
	input        mm_done,        // "done" pulse from matrix_multiplier_2x2

	output       busy,           // 1 whenever a MAT_* sequence is in flight -> freezes PC
	output       ovr_active,     // 1 -> top must route the mem bus to the ovr_* signals
	output [7:0] ovr_mem_addr,
	output [7:0] ovr_mem_wdata,
	output       ovr_mem_write,

	output [31:0] a_flat,
	output [31:0] b_flat,
	output        mm_write_mem,  // feeds matrix_multiplier_2x2.write_mem
	output        mm_start       // feeds matrix_multiplier_2x2.start
);

localparam S_IDLE      = 3'd0,
           S_LD_READ   = 3'd1,  // cnt = 0..3: read one byte/cycle, assemble word
           S_LD_LATCH  = 3'd2,  // present the assembled word for exactly 1 cycle
           S_MUL_PULSE = 3'd3,  // pulse start for exactly 1 cycle
           S_MUL_WAIT  = 3'd4,  // wait for mm_done
           S_ST_WRITE  = 3'd5;  // cnt = 0..7: write one byte/cycle

reg [2:0]  state, state_n;
reg [2:0]  cnt, cnt_n;
reg [31:0] ld_shadow, ld_shadow_n;
reg [7:0]  base_addr_r, base_addr_r_n;
reg        ld_target, ld_target_n;
reg [31:0] a_flat_r, a_flat_r_n;
reg [31:0] b_flat_r, b_flat_r_n;

// ---------------- combinational next-state / datapath ----------------
always @(*) begin
    state_n       = state;
    cnt_n         = cnt;
    ld_shadow_n   = ld_shadow;
    base_addr_r_n = base_addr_r;
    ld_target_n   = ld_target;
    a_flat_r_n    = a_flat_r;
    b_flat_r_n    = b_flat_r;

    case(state)
        S_IDLE: begin
            if (mat_ld) begin
                base_addr_r_n = base_addr;
                ld_target_n   = mat_ld_sel;
                cnt_n         = 3'd0;
                state_n       = S_LD_READ;
            end else if (mat_mul) begin
                state_n = S_MUL_PULSE;
            end else if (mat_st) begin
                base_addr_r_n = base_addr;
                cnt_n         = 3'd0;
                state_n       = S_ST_WRITE;
            end
        end

        S_LD_READ: begin
            // ovr_mem_addr this cycle = base_addr_r + cnt (see comb section below);
            // mem_read_data reflects that address combinationally, same cycle.
            if (cnt == 3'd3) begin
                // Last byte: assemble the complete word AND latch it straight
                // into the target register on this same edge, so it is
                // already valid throughout the S_LD_LATCH cycle that follows
                // (matching the cycle mm_write_mem pulses on -- no extra
                // one-cycle lag between "word ready" and "word presented").
                if (ld_target) b_flat_r_n = {mem_read_data, ld_shadow[23:0]};
                else            a_flat_r_n = {mem_read_data, ld_shadow[23:0]};
                state_n = S_LD_LATCH;
            end else begin
                case (cnt)
                    3'd0: ld_shadow_n[7:0]   = mem_read_data;
                    3'd1: ld_shadow_n[15:8]  = mem_read_data;
                    default: ld_shadow_n[23:16] = mem_read_data;
                endcase
                cnt_n = cnt + 3'd1;
            end
        end

        S_LD_LATCH: begin
            // a_flat_r/b_flat_r already hold the correct, complete word
            // (latched above); this cycle just presents mm_write_mem so
            // matrix_multiplier_2x2 captures it, then we're done.
            state_n = S_IDLE;
        end

        S_MUL_PULSE: begin
            state_n = S_MUL_WAIT;
        end

        S_MUL_WAIT: begin
            if (mm_done) state_n = S_IDLE;
        end

        S_ST_WRITE: begin
            if (cnt == 3'd7) state_n = S_IDLE;
            else             cnt_n   = cnt + 3'd1;
        end

        default: state_n = S_IDLE;
    endcase
end

// ---------------- sequential state update ----------------
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state       <= S_IDLE;
        cnt         <= 3'd0;
        ld_shadow   <= 32'd0;
        base_addr_r <= 8'd0;
        ld_target   <= 1'b0;
        a_flat_r    <= 32'd0;
        b_flat_r    <= 32'd0;
    end else begin
        state       <= state_n;
        cnt         <= cnt_n;
        ld_shadow   <= ld_shadow_n;
        base_addr_r <= base_addr_r_n;
        ld_target   <= ld_target_n;
        a_flat_r    <= a_flat_r_n;
        b_flat_r    <= b_flat_r_n;
    end
end

// ---------------- combinational output generation ----------------
assign busy        = (state != S_IDLE);
assign ovr_active  = (state == S_LD_READ) || (state == S_ST_WRITE);
assign ovr_mem_addr = base_addr_r + {5'd0, cnt};

reg [7:0] st_byte;
always @(*) begin
    case (cnt)
        3'd0: st_byte = c_out_0_0[7:0];
        3'd1: st_byte = c_out_0_0[15:8];
        3'd2: st_byte = c_out_0_1[7:0];
        3'd3: st_byte = c_out_0_1[15:8];
        3'd4: st_byte = c_out_1_0[7:0];
        3'd5: st_byte = c_out_1_0[15:8];
        3'd6: st_byte = c_out_1_1[7:0];
        default: st_byte = c_out_1_1[15:8];
    endcase
end
assign ovr_mem_wdata = st_byte;
assign ovr_mem_write = (state == S_ST_WRITE);

assign a_flat       = a_flat_r;
assign b_flat        = b_flat_r;
assign mm_write_mem  = (state == S_LD_LATCH) ? ld_target : 1'b0;
assign mm_start       = (state == S_MUL_PULSE);

endmodule


// ============================================================================
// ============================================================================
//   MATRIX MULTIPLIER SUB-SYSTEM  (folded in from matrix_2x2.v)
//   Provides: matrix_multiplier_2x2 (instantiated above in "top") and all of
//   its internal building blocks: pe_cell, multiplier_dadda, adder_stage,
//   cla_adder16, cla_adder14, cla_block4, cla_block2, and_gate, full_add,
//   half_add, dff, twos_complement.
// ============================================================================
// ============================================================================

// ============================================================================
// MAIN MODULE: matrix_multiplier_2x2  (reduced from the 8x8 design above)
// ============================================================================
// Computes C = A * B for 2x2 matrices of signed 8-bit elements.
//
// Ports:
//   a_flat[(2*2*8)-1:0]  = matrix A flattened row-major, 8-bit signed elements
//                          a_flat[8*(i*2+k)+:8] = A[i][k]
//   b_flat[(2*2*8)-1:0]  = matrix B flattened row-major
//                          b_flat[8*(k*2+j)+:8] = B[k][j]
//   write_mem            = 0 -> load a_flat into a_flat_reg
//                          1 -> load b_flat into b_flat_reg  (one per clock)
//   start                = pulse to begin computation
//   done                 = pulses high when both c_out registers are valid
//   c_out_i_j            = C[i][j], signed 17-bit register (exact width for
//                          a sum of 2 signed 8x8 products, see note below)
//
// Since a 2x2 dot-product only sums TWO terms:
//     C[i][j] = A[i][0]*B[0][j] + A[i][1]*B[1][j]
// the multi-level adder tree used in the 8x8 design collapses to a SINGLE
// adder_stage per output element (no L2/L3 needed), and only 2*2*2 = 8
// multipliers (pe_cell instances) are required in total (instead of 512).
//
// Output width: each 8x8-signed product needs 16 bits; summing 2 of them
// needs exactly 17 bits (max magnitude 2*16384=32768, which just exceeds a
// 16-bit signed range but fits exactly in 17 bits) -- no extra padding.
//
// Latency: 8 cycles (multiplier_dadda pipeline) + 1 cycle (adder_stage) = 9
// cycles from "start" to "done".
// ============================================================================
module matrix_multiplier_2x2 (
    input                   clk,
    input                   rst_n,

    // Matrix A: 2x2 of signed 8-bit values, row-major
    // a_flat[8*(i*2+k) +: 8] = A[i][k]
    input      [2*2*8-1:0]  a_flat,

    // Matrix B: 2x2 of signed 8-bit values, row-major
    // b_flat[8*(k*2+j) +: 8] = B[k][j]
    input      [2*2*8-1:0]  b_flat,

    // Control
    input                   start,      // pulse to begin a new multiplication
    input                   write_mem,  // 0 = load a_flat into a_flat_reg, 1 = load b_flat into b_flat_reg

    // Outputs — one dedicated 17-bit register per result element C[i][j]
    output reg signed [16:0] c_out_0_0, c_out_0_1,
    output reg signed [16:0] c_out_1_0, c_out_1_1,
    output reg                done      // pulses for 1 cycle when both c_out registers are valid
);

    // -----------------------------------------------------------------------
    // Input registers for a_flat / b_flat
    // A single write_mem signal selects which register gets loaded this cycle:
    //   write_mem == 0  ->  a_flat_reg <= a_flat
    //   write_mem == 1  ->  b_flat_reg <= b_flat
    // Only one of the two registers updates per clock; the other holds its
    // previous value.
    // -----------------------------------------------------------------------
    reg [2*2*8-1:0] a_flat_reg;
    reg [2*2*8-1:0] b_flat_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_flat_reg <= {(2*2*8){1'b0}};
            b_flat_reg <= {(2*2*8){1'b0}};
        end else begin
            if (write_mem == 1'b0)
                a_flat_reg <= a_flat;
            else
                b_flat_reg <= b_flat;
        end
    end

    // -----------------------------------------------------------------------
    // Fully parallel: 2*2*2 = 8 multipliers, one per (i,k,j) triple.
    // Each multiplier gets a FIXED pair (A[i][k], B[k][j]) -- no k-stepping.
    // "start" latches the inputs; results arrive 9 cycles later.
    // prod3d[i][k][j] = A[i][k] * B[k][j]  (16-bit signed product)
    // -----------------------------------------------------------------------
    wire signed [15:0] prod3d [0:1][0:1][0:1];  // [i][k][j]

    genvar gi, gk, gj;
    generate
        for (gi = 0; gi < 2; gi = gi + 1) begin : gen_pe_i
            for (gk = 0; gk < 2; gk = gk + 1) begin : gen_pe_k
                for (gj = 0; gj < 2; gj = gj + 1) begin : gen_pe_j
                    pe_cell u_pe3d (
                        .clk     (clk),
                        .rst_n   (rst_n),
                        .a_in    (a_flat_reg[8*(gi*2 + gk) +: 8]),  // A[i][k]
                        .b_in    (b_flat_reg[8*(gk*2 + gj) +: 8]),  // B[k][j]
                        .product (prod3d[gi][gk][gj])
                    );
                end
            end
        end
    endgenerate

    // -----------------------------------------------------------------------
    // Adder tree for each (i,j): sum over k=0,1 -- a SINGLE adder_stage
    // (16-bit product -> 17-bit sum), one pipeline register per element.
    // -----------------------------------------------------------------------
    wire signed [16:0] c_sum [0:1][0:1];

    generate
        for (gi = 0; gi < 2; gi = gi + 1) begin : tree_i
            for (gj = 0; gj < 2; gj = gj + 1) begin : tree_j
                adder_stage #(.WIDTH(17)) final_add (
                    .clk     (clk), .rst_n(rst_n),
                    .a_in    ({prod3d[gi][0][gj][15], prod3d[gi][0][gj]}),
                    .b_in    ({prod3d[gi][1][gj][15], prod3d[gi][1][gj]}),
                    .sum_out (c_sum[gi][gj])
                );
            end
        end
    endgenerate

    // -----------------------------------------------------------------------
    // Output capture: 9 cycles after start, latch each result into its own
    // dedicated register.  A 9-bit shift register propagates the start pulse
    // through the pipeline; bit [8] fires exactly when c_sum[i][j] is valid.
    // -----------------------------------------------------------------------
    reg [8:0] start_pipe;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            start_pipe <= 9'b0;
            done       <= 1'b0;
            c_out_0_0  <= 17'sd0; c_out_0_1 <= 17'sd0;
            c_out_1_0  <= 17'sd0; c_out_1_1 <= 17'sd0;
        end else begin
            start_pipe <= {start_pipe[7:0], start};
            done       <= start_pipe[8];  // valid on cycle 9

            if (start_pipe[8]) begin
                c_out_0_0 <= c_sum[0][0]; c_out_0_1 <= c_sum[0][1];
                c_out_1_0 <= c_sum[1][0]; c_out_1_1 <= c_sum[1][1];
            end
        end
    end

endmodule


// ============================================================================
// Each PE receives:
//   a_const[7:0]  : one fixed row of matrix A (all 8 elements packed:
//                   a_const[7:0] = A[row][k] for the current k)
//                   ** The TOP MODULE feeds the right element each cycle **
//   b_in[7:0]     : current B-column element (B[k][j])
//   k_valid       : strobe — PE captures a new multiply this cycle
//
// The PE just wraps multiplier_dadda.  Accumulation is done in the tree.
// (For the column-based scheme the 8 multiplications happen in 8 successive
// cycles; each PE accumulates its own dot-product row by row externally via
// the adder tree.  Here we present the raw 16-bit product and let the outer
// accumulator handle summation.)
// ============================================================================
module pe_cell (
    input        clk,
    input        rst_n,
    input  signed [7:0] a_in,
    input  signed [7:0] b_in,
    output signed [15:0] product
);
    multiplier_dadda u_mul (
        .clk   (clk),
        .rst_n (rst_n),
        .a     (a_in),
        .b     (b_in),
        .sum   (product)
    );
endmodule


// ============================================================================
// PIPELINED ADDER STAGE  (CLA16 for low 16 bits + registered output)
// ============================================================================
// Parameterized by WIDTH so each tree level uses only the exact number of
// bits its sum range requires (17/18/19 bits here) instead of a fixed 32.
// The lower 16 bits still go through the CLA16 adder; any extra high bits
// (WIDTH-16, which is only 1-3 bits in this design) are summed directly
// with the carry-out from the low CLA stage.
// ============================================================================
module adder_stage #(
    parameter WIDTH = 17
) (
    input         clk,
    input         rst_n,
    input  signed [WIDTH-1:0] a_in,
    input  signed [WIDTH-1:0] b_in,
    output reg signed [WIDTH-1:0] sum_out
);
    wire [WIDTH-1:0] comb_sum;
    wire        cout_lo;

    cla_adder16 lo (.a(a_in[15:0]), .b(b_in[15:0]), .cin(1'b0), .sum(comb_sum[15:0]), .cout(cout_lo));

    // Extra high bits (WIDTH-16 of them) beyond the CLA16 lower half
    assign comb_sum[WIDTH-1:16] = a_in[WIDTH-1:16] + b_in[WIDTH-1:16] + cout_lo;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) sum_out <= {WIDTH{1'b0}};
        else        sum_out <= comb_sum;
    end
endmodule


// ============================================================================
// NOTES ON MODULE DEPENDENCIES (files that must be compiled together)
// ============================================================================
// This file requires the following modules from multiplier.v:
//   - multiplier_dadda
//   - dff
//   - and_gate
//   - cla_block4
//   - cla_block2
//   - cla_adder14
//   - full_add
//   - half_add
//   - twos_complement
// ============================================================================
// 8x8 SIGNED Dadda multiplier -- PIPELINED, sign-magnitude implementation
//
// Strategy: two's-complement inputs are converted to sign + magnitude, the
// (unsigned) magnitudes are multiplied with the ORIGINAL unsigned Dadda-tree
// AND-array/reduction pipeline (unchanged), and the magnitude result is
// negated back to two's complement at the very end only if the operand signs
// differed. All pipeline registers are instances of the `dff` module
// (asynchronous active-low reset); sign negation uses the `twos_complement`
// module.
//
// Pipeline stages (one clocked register bank between each):
//   R0 : input registers for a, b                          ("taking in data")
//   S1 (comb): sign/magnitude extraction + AND-array PP gen -> R1
//   S2 (comb): Dadda reduction 1  (height 8 -> 6)            -> R2
//   S3 (comb): Dadda reduction 2  (height 6 -> 4)            -> R3
//   S4 (comb): Dadda reduction 3  (height 4 -> 3)            -> R4
//   S5 (comb): Dadda reduction 4  (height 3 -> 2)            -> R5
//   S6 (comb): final vector-merge add (14-bit CLA)           -> R6 (magnitude result)
//   S7 (comb): conditional two's-complement sign correction  -> R7 (= sum, final)
//
// Latency: 8 clock cycles from a/b being presented to sum being valid.
// A new a/b pair may be accepted every clock cycle (fully pipelined).

module multiplier_dadda(
    input               clk,
    input               rst_n,   // asynchronous, active-low: clears the whole pipeline
    input signed  [7:0] a,
    input signed  [7:0] b,
    output signed [15:0] sum
);

  // ---------------------------------------------------------------------
  // R0 : register the incoming operands (the pipeline's data-in stage)
  // ---------------------------------------------------------------------
  wire [7:0] a_q0, b_q0;
  dff #(8) u_reg_a (.clk(clk), .rst_n(rst_n), .d(a), .q(a_q0));
  dff #(8) u_reg_b (.clk(clk), .rst_n(rst_n), .d(b), .q(b_q0));

  // ---------------------------------------------------------------------
  // S1 (comb): sign extraction, magnitude conversion, partial-product gen
  // ---------------------------------------------------------------------
  wire sign_a = a_q0[7];
  wire sign_b = b_q0[7];
  wire result_sign = sign_a ^ sign_b;   // product is negative iff signs differ

  wire [7:0] a_neg, b_neg;
  twos_complement #(8) u_neg_a (.in(a_q0), .out(a_neg));
  twos_complement #(8) u_neg_b (.in(b_q0), .out(b_neg));

  // magnitude of each operand (its absolute value, as an unsigned 8-bit bus)
  wire [7:0] mag_a = sign_a ? a_neg : a_q0;
  wire [7:0] mag_b = sign_b ? b_neg : b_q0;

  // unchanged unsigned AND-array: multiplies the two MAGNITUDES
  wire p00, p01, p02, p03, p04, p05, p06, p07;
  wire p10, p11, p12, p13, p14, p15, p16, p17;
  wire p20, p21, p22, p23, p24, p25, p26, p27;
  wire p30, p31, p32, p33, p34, p35, p36, p37;
  wire p40, p41, p42, p43, p44, p45, p46, p47;
  wire p50, p51, p52, p53, p54, p55, p56, p57;
  wire p60, p61, p62, p63, p64, p65, p66, p67;
  wire p70, p71, p72, p73, p74, p75, p76, p77;

  //AND-gate instances for row0: p0{col} = mag_a[{col}] & mag_b[0]
  and_gate u_p00 (.a(mag_a[0]), .b(mag_b[0]), .p(p00));
  and_gate u_p01 (.a(mag_a[1]), .b(mag_b[0]), .p(p01));
  and_gate u_p02 (.a(mag_a[2]), .b(mag_b[0]), .p(p02));
  and_gate u_p03 (.a(mag_a[3]), .b(mag_b[0]), .p(p03));
  and_gate u_p04 (.a(mag_a[4]), .b(mag_b[0]), .p(p04));
  and_gate u_p05 (.a(mag_a[5]), .b(mag_b[0]), .p(p05));
  and_gate u_p06 (.a(mag_a[6]), .b(mag_b[0]), .p(p06));
  and_gate u_p07 (.a(mag_a[7]), .b(mag_b[0]), .p(p07));

  //AND-gate instances for row1: p1{col} = mag_a[{col}] & mag_b[1]
  and_gate u_p10 (.a(mag_a[0]), .b(mag_b[1]), .p(p10));
  and_gate u_p11 (.a(mag_a[1]), .b(mag_b[1]), .p(p11));
  and_gate u_p12 (.a(mag_a[2]), .b(mag_b[1]), .p(p12));
  and_gate u_p13 (.a(mag_a[3]), .b(mag_b[1]), .p(p13));
  and_gate u_p14 (.a(mag_a[4]), .b(mag_b[1]), .p(p14));
  and_gate u_p15 (.a(mag_a[5]), .b(mag_b[1]), .p(p15));
  and_gate u_p16 (.a(mag_a[6]), .b(mag_b[1]), .p(p16));
  and_gate u_p17 (.a(mag_a[7]), .b(mag_b[1]), .p(p17));

  //AND-gate instances for row2: p2{col} = mag_a[{col}] & mag_b[2]
  and_gate u_p20 (.a(mag_a[0]), .b(mag_b[2]), .p(p20));
  and_gate u_p21 (.a(mag_a[1]), .b(mag_b[2]), .p(p21));
  and_gate u_p22 (.a(mag_a[2]), .b(mag_b[2]), .p(p22));
  and_gate u_p23 (.a(mag_a[3]), .b(mag_b[2]), .p(p23));
  and_gate u_p24 (.a(mag_a[4]), .b(mag_b[2]), .p(p24));
  and_gate u_p25 (.a(mag_a[5]), .b(mag_b[2]), .p(p25));
  and_gate u_p26 (.a(mag_a[6]), .b(mag_b[2]), .p(p26));
  and_gate u_p27 (.a(mag_a[7]), .b(mag_b[2]), .p(p27));

  //AND-gate instances for row3: p3{col} = mag_a[{col}] & mag_b[3]
  and_gate u_p30 (.a(mag_a[0]), .b(mag_b[3]), .p(p30));
  and_gate u_p31 (.a(mag_a[1]), .b(mag_b[3]), .p(p31));
  and_gate u_p32 (.a(mag_a[2]), .b(mag_b[3]), .p(p32));
  and_gate u_p33 (.a(mag_a[3]), .b(mag_b[3]), .p(p33));
  and_gate u_p34 (.a(mag_a[4]), .b(mag_b[3]), .p(p34));
  and_gate u_p35 (.a(mag_a[5]), .b(mag_b[3]), .p(p35));
  and_gate u_p36 (.a(mag_a[6]), .b(mag_b[3]), .p(p36));
  and_gate u_p37 (.a(mag_a[7]), .b(mag_b[3]), .p(p37));

  //AND-gate instances for row4: p4{col} = mag_a[{col}] & mag_b[4]
  and_gate u_p40 (.a(mag_a[0]), .b(mag_b[4]), .p(p40));
  and_gate u_p41 (.a(mag_a[1]), .b(mag_b[4]), .p(p41));
  and_gate u_p42 (.a(mag_a[2]), .b(mag_b[4]), .p(p42));
  and_gate u_p43 (.a(mag_a[3]), .b(mag_b[4]), .p(p43));
  and_gate u_p44 (.a(mag_a[4]), .b(mag_b[4]), .p(p44));
  and_gate u_p45 (.a(mag_a[5]), .b(mag_b[4]), .p(p45));
  and_gate u_p46 (.a(mag_a[6]), .b(mag_b[4]), .p(p46));
  and_gate u_p47 (.a(mag_a[7]), .b(mag_b[4]), .p(p47));

  //AND-gate instances for row5: p5{col} = mag_a[{col}] & mag_b[5]
  and_gate u_p50 (.a(mag_a[0]), .b(mag_b[5]), .p(p50));
  and_gate u_p51 (.a(mag_a[1]), .b(mag_b[5]), .p(p51));
  and_gate u_p52 (.a(mag_a[2]), .b(mag_b[5]), .p(p52));
  and_gate u_p53 (.a(mag_a[3]), .b(mag_b[5]), .p(p53));
  and_gate u_p54 (.a(mag_a[4]), .b(mag_b[5]), .p(p54));
  and_gate u_p55 (.a(mag_a[5]), .b(mag_b[5]), .p(p55));
  and_gate u_p56 (.a(mag_a[6]), .b(mag_b[5]), .p(p56));
  and_gate u_p57 (.a(mag_a[7]), .b(mag_b[5]), .p(p57));

  //AND-gate instances for row6: p6{col} = mag_a[{col}] & mag_b[6]
  and_gate u_p60 (.a(mag_a[0]), .b(mag_b[6]), .p(p60));
  and_gate u_p61 (.a(mag_a[1]), .b(mag_b[6]), .p(p61));
  and_gate u_p62 (.a(mag_a[2]), .b(mag_b[6]), .p(p62));
  and_gate u_p63 (.a(mag_a[3]), .b(mag_b[6]), .p(p63));
  and_gate u_p64 (.a(mag_a[4]), .b(mag_b[6]), .p(p64));
  and_gate u_p65 (.a(mag_a[5]), .b(mag_b[6]), .p(p65));
  and_gate u_p66 (.a(mag_a[6]), .b(mag_b[6]), .p(p66));
  and_gate u_p67 (.a(mag_a[7]), .b(mag_b[6]), .p(p67));

  //AND-gate instances for row7: p7{col} = mag_a[{col}] & mag_b[7]
  and_gate u_p70 (.a(mag_a[0]), .b(mag_b[7]), .p(p70));
  and_gate u_p71 (.a(mag_a[1]), .b(mag_b[7]), .p(p71));
  and_gate u_p72 (.a(mag_a[2]), .b(mag_b[7]), .p(p72));
  and_gate u_p73 (.a(mag_a[3]), .b(mag_b[7]), .p(p73));
  and_gate u_p74 (.a(mag_a[4]), .b(mag_b[7]), .p(p74));
  and_gate u_p75 (.a(mag_a[5]), .b(mag_b[7]), .p(p75));
  and_gate u_p76 (.a(mag_a[6]), .b(mag_b[7]), .p(p76));
  and_gate u_p77 (.a(mag_a[7]), .b(mag_b[7]), .p(p77));

  // ---------------------------------------------------------------------
  // Pipeline register bank R1 : all 64 partial-product bits + result_sign (1st hop)
  // ---------------------------------------------------------------------
  wire [64:0] bank1_d = {result_sign, p77, p76, p75, p74, p73, p72, p71, p70, p67, p66, p65, p64, p63, p62, p61, p60, p57, p56, p55, p54, p53, p52, p51, p50, p47, p46, p45, p44, p43, p42, p41, p40, p37, p36, p35, p34, p33, p32, p31, p30, p27, p26, p25, p24, p23, p22, p21, p20, p17, p16, p15, p14, p13, p12, p11, p10, p07, p06, p05, p04, p03, p02, p01, p00};
  wire [64:0] bank1_q;
  dff #(65) u_bank1 (.clk(clk), .rst_n(rst_n), .d(bank1_d), .q(bank1_q));

  wire p00_q1 = bank1_q[0];
  wire p01_q1 = bank1_q[1];
  wire p02_q1 = bank1_q[2];
  wire p03_q1 = bank1_q[3];
  wire p04_q1 = bank1_q[4];
  wire p05_q1 = bank1_q[5];
  wire p06_q1 = bank1_q[6];
  wire p07_q1 = bank1_q[7];
  wire p10_q1 = bank1_q[8];
  wire p11_q1 = bank1_q[9];
  wire p12_q1 = bank1_q[10];
  wire p13_q1 = bank1_q[11];
  wire p14_q1 = bank1_q[12];
  wire p15_q1 = bank1_q[13];
  wire p16_q1 = bank1_q[14];
  wire p17_q1 = bank1_q[15];
  wire p20_q1 = bank1_q[16];
  wire p21_q1 = bank1_q[17];
  wire p22_q1 = bank1_q[18];
  wire p23_q1 = bank1_q[19];
  wire p24_q1 = bank1_q[20];
  wire p25_q1 = bank1_q[21];
  wire p26_q1 = bank1_q[22];
  wire p27_q1 = bank1_q[23];
  wire p30_q1 = bank1_q[24];
  wire p31_q1 = bank1_q[25];
  wire p32_q1 = bank1_q[26];
  wire p33_q1 = bank1_q[27];
  wire p34_q1 = bank1_q[28];
  wire p35_q1 = bank1_q[29];
  wire p36_q1 = bank1_q[30];
  wire p37_q1 = bank1_q[31];
  wire p40_q1 = bank1_q[32];
  wire p41_q1 = bank1_q[33];
  wire p42_q1 = bank1_q[34];
  wire p43_q1 = bank1_q[35];
  wire p44_q1 = bank1_q[36];
  wire p45_q1 = bank1_q[37];
  wire p46_q1 = bank1_q[38];
  wire p47_q1 = bank1_q[39];
  wire p50_q1 = bank1_q[40];
  wire p51_q1 = bank1_q[41];
  wire p52_q1 = bank1_q[42];
  wire p53_q1 = bank1_q[43];
  wire p54_q1 = bank1_q[44];
  wire p55_q1 = bank1_q[45];
  wire p56_q1 = bank1_q[46];
  wire p57_q1 = bank1_q[47];
  wire p60_q1 = bank1_q[48];
  wire p61_q1 = bank1_q[49];
  wire p62_q1 = bank1_q[50];
  wire p63_q1 = bank1_q[51];
  wire p64_q1 = bank1_q[52];
  wire p65_q1 = bank1_q[53];
  wire p66_q1 = bank1_q[54];
  wire p67_q1 = bank1_q[55];
  wire p70_q1 = bank1_q[56];
  wire p71_q1 = bank1_q[57];
  wire p72_q1 = bank1_q[58];
  wire p73_q1 = bank1_q[59];
  wire p74_q1 = bank1_q[60];
  wire p75_q1 = bank1_q[61];
  wire p76_q1 = bank1_q[62];
  wire p77_q1 = bank1_q[63];
  wire result_sign_q1 = bank1_q[64];

  // ---------------------------------------------------------------------
  // S2 (comb): Dadda reduction stage 1 (target column height 6)
  // ---------------------------------------------------------------------
wire s7_1_1,c7_1_1,s8_1_1,c8_1_1,s8_1_2,c8_1_2,s9_1_1,c9_1_1,s9_1_2,c9_1_2,s10_1_1,c10_1_1;
  half_add ha_c7_s1_1 (.a(p06_q1), .b(p15_q1), .sum(s7_1_1), .carry(c7_1_1));
  full_add fa_c8_s1_1 (.a(p07_q1), .b(p16_q1), .c(p25_q1), .sum(s8_1_1), .carry(c8_1_1));
  half_add ha_c8_s1_2 (.a(p34_q1), .b(p43_q1), .sum(s8_1_2), .carry(c8_1_2));
  full_add fa_c9_s1_1 (.a(p17_q1), .b(p26_q1), .c(p35_q1), .sum(s9_1_1), .carry(c9_1_1));
  half_add ha_c9_s1_2 (.a(p44_q1), .b(p53_q1), .sum(s9_1_2), .carry(c9_1_2));
  full_add fa_c10_s1_1 (.a(p27_q1), .b(p36_q1), .c(p45_q1), .sum(s10_1_1), .carry(c10_1_1));

  // ---------------------------------------------------------------------
  // Pipeline register bank R2 : stage-1 outputs + carried-forward bits
  // ---------------------------------------------------------------------
  wire [61:0] bank2_d = {result_sign_q1, c10_1_1, s10_1_1, c9_1_2, s9_1_2, c9_1_1, s9_1_1, c8_1_2, s8_1_2, c8_1_1, s8_1_1, c7_1_1, s7_1_1, p77_q1, p76_q1, p75_q1, p74_q1, p73_q1, p72_q1, p71_q1, p70_q1, p67_q1, p66_q1, p65_q1, p64_q1, p63_q1, p62_q1, p61_q1, p60_q1, p57_q1, p56_q1, p55_q1, p54_q1, p52_q1, p51_q1, p50_q1, p47_q1, p46_q1, p42_q1, p41_q1, p40_q1, p37_q1, p33_q1, p32_q1, p31_q1, p30_q1, p24_q1, p23_q1, p22_q1, p21_q1, p20_q1, p14_q1, p13_q1, p12_q1, p11_q1, p10_q1, p05_q1, p04_q1, p03_q1, p02_q1, p01_q1, p00_q1};
  wire [61:0] bank2_q;
  dff #(62) u_bank2 (.clk(clk), .rst_n(rst_n), .d(bank2_d), .q(bank2_q));

  wire p00_q2 = bank2_q[0];
  wire p01_q2 = bank2_q[1];
  wire p02_q2 = bank2_q[2];
  wire p03_q2 = bank2_q[3];
  wire p04_q2 = bank2_q[4];
  wire p05_q2 = bank2_q[5];
  wire p10_q2 = bank2_q[6];
  wire p11_q2 = bank2_q[7];
  wire p12_q2 = bank2_q[8];
  wire p13_q2 = bank2_q[9];
  wire p14_q2 = bank2_q[10];
  wire p20_q2 = bank2_q[11];
  wire p21_q2 = bank2_q[12];
  wire p22_q2 = bank2_q[13];
  wire p23_q2 = bank2_q[14];
  wire p24_q2 = bank2_q[15];
  wire p30_q2 = bank2_q[16];
  wire p31_q2 = bank2_q[17];
  wire p32_q2 = bank2_q[18];
  wire p33_q2 = bank2_q[19];
  wire p37_q2 = bank2_q[20];
  wire p40_q2 = bank2_q[21];
  wire p41_q2 = bank2_q[22];
  wire p42_q2 = bank2_q[23];
  wire p46_q2 = bank2_q[24];
  wire p47_q2 = bank2_q[25];
  wire p50_q2 = bank2_q[26];
  wire p51_q2 = bank2_q[27];
  wire p52_q2 = bank2_q[28];
  wire p54_q2 = bank2_q[29];
  wire p55_q2 = bank2_q[30];
  wire p56_q2 = bank2_q[31];
  wire p57_q2 = bank2_q[32];
  wire p60_q2 = bank2_q[33];
  wire p61_q2 = bank2_q[34];
  wire p62_q2 = bank2_q[35];
  wire p63_q2 = bank2_q[36];
  wire p64_q2 = bank2_q[37];
  wire p65_q2 = bank2_q[38];
  wire p66_q2 = bank2_q[39];
  wire p67_q2 = bank2_q[40];
  wire p70_q2 = bank2_q[41];
  wire p71_q2 = bank2_q[42];
  wire p72_q2 = bank2_q[43];
  wire p73_q2 = bank2_q[44];
  wire p74_q2 = bank2_q[45];
  wire p75_q2 = bank2_q[46];
  wire p76_q2 = bank2_q[47];
  wire p77_q2 = bank2_q[48];
  wire s7_1_1_q1 = bank2_q[49];
  wire c7_1_1_q1 = bank2_q[50];
  wire s8_1_1_q1 = bank2_q[51];
  wire c8_1_1_q1 = bank2_q[52];
  wire s8_1_2_q1 = bank2_q[53];
  wire c8_1_2_q1 = bank2_q[54];
  wire s9_1_1_q1 = bank2_q[55];
  wire c9_1_1_q1 = bank2_q[56];
  wire s9_1_2_q1 = bank2_q[57];
  wire c9_1_2_q1 = bank2_q[58];
  wire s10_1_1_q1 = bank2_q[59];
  wire c10_1_1_q1 = bank2_q[60];
  wire result_sign_q2 = bank2_q[61];

  // ---------------------------------------------------------------------
  // S3 (comb): Dadda reduction stage 2 (target column height 4)
  // ---------------------------------------------------------------------
wire s5_2_1,c5_2_1,s6_2_1,c6_2_1,s6_2_2,c6_2_2,s7_2_1,c7_2_1,s7_2_2,c7_2_2,s8_2_1,c8_2_1,s8_2_2,c8_2_2,s9_2_1,c9_2_1,s9_2_2,c9_2_2,s10_2_1,c10_2_1,s10_2_2,c10_2_2,s11_2_1,c11_2_1,s11_2_2,c11_2_2,s12_2_1,c12_2_1;
  half_add ha_c5_s2_1 (.a(p04_q2), .b(p13_q2), .sum(s5_2_1), .carry(c5_2_1));
  full_add fa_c6_s2_1 (.a(p05_q2), .b(p14_q2), .c(p23_q2), .sum(s6_2_1), .carry(c6_2_1));
  half_add ha_c6_s2_2 (.a(p32_q2), .b(p41_q2), .sum(s6_2_2), .carry(c6_2_2));
  full_add fa_c7_s2_1 (.a(p24_q2), .b(p33_q2), .c(p42_q2), .sum(s7_2_1), .carry(c7_2_1));
  full_add fa_c7_s2_2 (.a(p51_q2), .b(p60_q2), .c(s7_1_1_q1), .sum(s7_2_2), .carry(c7_2_2));
  full_add fa_c8_s2_1 (.a(p52_q2), .b(p61_q2), .c(p70_q2), .sum(s8_2_1), .carry(c8_2_1));
  full_add fa_c8_s2_2 (.a(c7_1_1_q1), .b(s8_1_1_q1), .c(s8_1_2_q1), .sum(s8_2_2), .carry(c8_2_2));
  full_add fa_c9_s2_1 (.a(p62_q2), .b(p71_q2), .c(c8_1_1_q1), .sum(s9_2_1), .carry(c9_2_1));
  full_add fa_c9_s2_2 (.a(c8_1_2_q1), .b(s9_1_1_q1), .c(s9_1_2_q1), .sum(s9_2_2), .carry(c9_2_2));
  full_add fa_c10_s2_1 (.a(p54_q2), .b(p63_q2), .c(p72_q2), .sum(s10_2_1), .carry(c10_2_1));
  full_add fa_c10_s2_2 (.a(c9_1_1_q1), .b(c9_1_2_q1), .c(s10_1_1_q1), .sum(s10_2_2), .carry(c10_2_2));
  full_add fa_c11_s2_1 (.a(p37_q2), .b(p46_q2), .c(p55_q2), .sum(s11_2_1), .carry(c11_2_1));
  full_add fa_c11_s2_2 (.a(p64_q2), .b(p73_q2), .c(c10_1_1_q1), .sum(s11_2_2), .carry(c11_2_2));
  full_add fa_c12_s2_1 (.a(p47_q2), .b(p56_q2), .c(p65_q2), .sum(s12_2_1), .carry(c12_2_1));

  // ---------------------------------------------------------------------
  // Pipeline register bank R3 : stage-2 outputs + carried-forward bits
  // ---------------------------------------------------------------------
  wire [49:0] bank3_d = {result_sign_q2, c12_2_1, s12_2_1, c11_2_2, s11_2_2, c11_2_1, s11_2_1, c10_2_2, s10_2_2, c10_2_1, s10_2_1, c9_2_2, s9_2_2, c9_2_1, s9_2_1, c8_2_2, s8_2_2, c8_2_1, s8_2_1, c7_2_2, s7_2_2, c7_2_1, s7_2_1, c6_2_2, s6_2_2, c6_2_1, s6_2_1, c5_2_1, s5_2_1, p77_q2, p76_q2, p75_q2, p74_q2, p67_q2, p66_q2, p57_q2, p50_q2, p40_q2, p31_q2, p30_q2, p22_q2, p21_q2, p20_q2, p12_q2, p11_q2, p10_q2, p03_q2, p02_q2, p01_q2, p00_q2};
  wire [49:0] bank3_q;
  dff #(50) u_bank3 (.clk(clk), .rst_n(rst_n), .d(bank3_d), .q(bank3_q));

  wire p00_q3 = bank3_q[0];
  wire p01_q3 = bank3_q[1];
  wire p02_q3 = bank3_q[2];
  wire p03_q3 = bank3_q[3];
  wire p10_q3 = bank3_q[4];
  wire p11_q3 = bank3_q[5];
  wire p12_q3 = bank3_q[6];
  wire p20_q3 = bank3_q[7];
  wire p21_q3 = bank3_q[8];
  wire p22_q3 = bank3_q[9];
  wire p30_q3 = bank3_q[10];
  wire p31_q3 = bank3_q[11];
  wire p40_q3 = bank3_q[12];
  wire p50_q3 = bank3_q[13];
  wire p57_q3 = bank3_q[14];
  wire p66_q3 = bank3_q[15];
  wire p67_q3 = bank3_q[16];
  wire p74_q3 = bank3_q[17];
  wire p75_q3 = bank3_q[18];
  wire p76_q3 = bank3_q[19];
  wire p77_q3 = bank3_q[20];
  wire s5_2_1_q1 = bank3_q[21];
  wire c5_2_1_q1 = bank3_q[22];
  wire s6_2_1_q1 = bank3_q[23];
  wire c6_2_1_q1 = bank3_q[24];
  wire s6_2_2_q1 = bank3_q[25];
  wire c6_2_2_q1 = bank3_q[26];
  wire s7_2_1_q1 = bank3_q[27];
  wire c7_2_1_q1 = bank3_q[28];
  wire s7_2_2_q1 = bank3_q[29];
  wire c7_2_2_q1 = bank3_q[30];
  wire s8_2_1_q1 = bank3_q[31];
  wire c8_2_1_q1 = bank3_q[32];
  wire s8_2_2_q1 = bank3_q[33];
  wire c8_2_2_q1 = bank3_q[34];
  wire s9_2_1_q1 = bank3_q[35];
  wire c9_2_1_q1 = bank3_q[36];
  wire s9_2_2_q1 = bank3_q[37];
  wire c9_2_2_q1 = bank3_q[38];
  wire s10_2_1_q1 = bank3_q[39];
  wire c10_2_1_q1 = bank3_q[40];
  wire s10_2_2_q1 = bank3_q[41];
  wire c10_2_2_q1 = bank3_q[42];
  wire s11_2_1_q1 = bank3_q[43];
  wire c11_2_1_q1 = bank3_q[44];
  wire s11_2_2_q1 = bank3_q[45];
  wire c11_2_2_q1 = bank3_q[46];
  wire s12_2_1_q1 = bank3_q[47];
  wire c12_2_1_q1 = bank3_q[48];
  wire result_sign_q3 = bank3_q[49];

  // ---------------------------------------------------------------------
  // S4 (comb): Dadda reduction stage 3 (target column height 3)
  // ---------------------------------------------------------------------
wire s4_3_1,c4_3_1,s5_3_1,c5_3_1,s6_3_1,c6_3_1,s7_3_1,c7_3_1,s8_3_1,c8_3_1,s9_3_1,c9_3_1,s10_3_1,c10_3_1,s11_3_1,c11_3_1,s12_3_1,c12_3_1,s13_3_1,c13_3_1;
  half_add ha_c4_s3_1 (.a(p03_q3), .b(p12_q3), .sum(s4_3_1), .carry(c4_3_1));
  full_add fa_c5_s3_1 (.a(p22_q3), .b(p31_q3), .c(p40_q3), .sum(s5_3_1), .carry(c5_3_1));
  full_add fa_c6_s3_1 (.a(p50_q3), .b(c5_2_1_q1), .c(s6_2_1_q1), .sum(s6_3_1), .carry(c6_3_1));
  full_add fa_c7_s3_1 (.a(c6_2_1_q1), .b(c6_2_2_q1), .c(s7_2_1_q1), .sum(s7_3_1), .carry(c7_3_1));
  full_add fa_c8_s3_1 (.a(c7_2_1_q1), .b(c7_2_2_q1), .c(s8_2_1_q1), .sum(s8_3_1), .carry(c8_3_1));
  full_add fa_c9_s3_1 (.a(c8_2_1_q1), .b(c8_2_2_q1), .c(s9_2_1_q1), .sum(s9_3_1), .carry(c9_3_1));
  full_add fa_c10_s3_1 (.a(c9_2_1_q1), .b(c9_2_2_q1), .c(s10_2_1_q1), .sum(s10_3_1), .carry(c10_3_1));
  full_add fa_c11_s3_1 (.a(c10_2_1_q1), .b(c10_2_2_q1), .c(s11_2_1_q1), .sum(s11_3_1), .carry(c11_3_1));
  full_add fa_c12_s3_1 (.a(p74_q3), .b(c11_2_1_q1), .c(c11_2_2_q1), .sum(s12_3_1), .carry(c12_3_1));
  full_add fa_c13_s3_1 (.a(p57_q3), .b(p66_q3), .c(p75_q3), .sum(s13_3_1), .carry(c13_3_1));

  // ---------------------------------------------------------------------
  // Pipeline register bank R4 : stage-3 outputs + carried-forward bits
  // ---------------------------------------------------------------------
  wire [40:0] bank4_d = {result_sign_q3, c13_3_1, s13_3_1, c12_3_1, s12_3_1, c11_3_1, s11_3_1, c10_3_1, s10_3_1, c9_3_1, s9_3_1, c8_3_1, s8_3_1, c7_3_1, s7_3_1, c6_3_1, s6_3_1, c5_3_1, s5_3_1, c4_3_1, s4_3_1, c12_2_1_q1, s12_2_1_q1, s11_2_2_q1, s10_2_2_q1, s9_2_2_q1, s8_2_2_q1, s7_2_2_q1, s6_2_2_q1, s5_2_1_q1, p77_q3, p76_q3, p67_q3, p30_q3, p21_q3, p20_q3, p11_q3, p10_q3, p02_q3, p01_q3, p00_q3};
  wire [40:0] bank4_q;
  dff #(41) u_bank4 (.clk(clk), .rst_n(rst_n), .d(bank4_d), .q(bank4_q));

  wire p00_q4 = bank4_q[0];
  wire p01_q4 = bank4_q[1];
  wire p02_q4 = bank4_q[2];
  wire p10_q4 = bank4_q[3];
  wire p11_q4 = bank4_q[4];
  wire p20_q4 = bank4_q[5];
  wire p21_q4 = bank4_q[6];
  wire p30_q4 = bank4_q[7];
  wire p67_q4 = bank4_q[8];
  wire p76_q4 = bank4_q[9];
  wire p77_q4 = bank4_q[10];
  wire s5_2_1_q2 = bank4_q[11];
  wire s6_2_2_q2 = bank4_q[12];
  wire s7_2_2_q2 = bank4_q[13];
  wire s8_2_2_q2 = bank4_q[14];
  wire s9_2_2_q2 = bank4_q[15];
  wire s10_2_2_q2 = bank4_q[16];
  wire s11_2_2_q2 = bank4_q[17];
  wire s12_2_1_q2 = bank4_q[18];
  wire c12_2_1_q2 = bank4_q[19];
  wire s4_3_1_q1 = bank4_q[20];
  wire c4_3_1_q1 = bank4_q[21];
  wire s5_3_1_q1 = bank4_q[22];
  wire c5_3_1_q1 = bank4_q[23];
  wire s6_3_1_q1 = bank4_q[24];
  wire c6_3_1_q1 = bank4_q[25];
  wire s7_3_1_q1 = bank4_q[26];
  wire c7_3_1_q1 = bank4_q[27];
  wire s8_3_1_q1 = bank4_q[28];
  wire c8_3_1_q1 = bank4_q[29];
  wire s9_3_1_q1 = bank4_q[30];
  wire c9_3_1_q1 = bank4_q[31];
  wire s10_3_1_q1 = bank4_q[32];
  wire c10_3_1_q1 = bank4_q[33];
  wire s11_3_1_q1 = bank4_q[34];
  wire c11_3_1_q1 = bank4_q[35];
  wire s12_3_1_q1 = bank4_q[36];
  wire c12_3_1_q1 = bank4_q[37];
  wire s13_3_1_q1 = bank4_q[38];
  wire c13_3_1_q1 = bank4_q[39];
  wire result_sign_q4 = bank4_q[40];

  // ---------------------------------------------------------------------
  // S5 (comb): Dadda reduction stage 4 (target column height 2)
  // ---------------------------------------------------------------------
wire s3_4_1,c3_4_1,s4_4_1,c4_4_1,s5_4_1,c5_4_1,s6_4_1,c6_4_1,s7_4_1,c7_4_1,s8_4_1,c8_4_1,s9_4_1,c9_4_1,s10_4_1,c10_4_1,s11_4_1,c11_4_1,s12_4_1,c12_4_1,s13_4_1,c13_4_1,s14_4_1,c14_4_1;
  half_add ha_c3_s4_1 (.a(p02_q4), .b(p11_q4), .sum(s3_4_1), .carry(c3_4_1));
  full_add fa_c4_s4_1 (.a(p21_q4), .b(p30_q4), .c(s4_3_1_q1), .sum(s4_4_1), .carry(c4_4_1));
  full_add fa_c5_s4_1 (.a(s5_2_1_q2), .b(c4_3_1_q1), .c(s5_3_1_q1), .sum(s5_4_1), .carry(c5_4_1));
  full_add fa_c6_s4_1 (.a(s6_2_2_q2), .b(c5_3_1_q1), .c(s6_3_1_q1), .sum(s6_4_1), .carry(c6_4_1));
  full_add fa_c7_s4_1 (.a(s7_2_2_q2), .b(c6_3_1_q1), .c(s7_3_1_q1), .sum(s7_4_1), .carry(c7_4_1));
  full_add fa_c8_s4_1 (.a(s8_2_2_q2), .b(c7_3_1_q1), .c(s8_3_1_q1), .sum(s8_4_1), .carry(c8_4_1));
  full_add fa_c9_s4_1 (.a(s9_2_2_q2), .b(c8_3_1_q1), .c(s9_3_1_q1), .sum(s9_4_1), .carry(c9_4_1));
  full_add fa_c10_s4_1 (.a(s10_2_2_q2), .b(c9_3_1_q1), .c(s10_3_1_q1), .sum(s10_4_1), .carry(c10_4_1));
  full_add fa_c11_s4_1 (.a(s11_2_2_q2), .b(c10_3_1_q1), .c(s11_3_1_q1), .sum(s11_4_1), .carry(c11_4_1));
  full_add fa_c12_s4_1 (.a(s12_2_1_q2), .b(c11_3_1_q1), .c(s12_3_1_q1), .sum(s12_4_1), .carry(c12_4_1));
  full_add fa_c13_s4_1 (.a(c12_2_1_q2), .b(c12_3_1_q1), .c(s13_3_1_q1), .sum(s13_4_1), .carry(c13_4_1));
  full_add fa_c14_s4_1 (.a(p67_q4), .b(p76_q4), .c(c13_3_1_q1), .sum(s14_4_1), .carry(c14_4_1));

  // ---------------------------------------------------------------------
  // Pipeline register bank R5 : stage-4 outputs + carried-forward bits
  // ---------------------------------------------------------------------
  wire [29:0] bank5_d = {result_sign_q4, c14_4_1, s14_4_1, c13_4_1, s13_4_1, c12_4_1, s12_4_1, c11_4_1, s11_4_1, c10_4_1, s10_4_1, c9_4_1, s9_4_1, c8_4_1, s8_4_1, c7_4_1, s7_4_1, c6_4_1, s6_4_1, c5_4_1, s5_4_1, c4_4_1, s4_4_1, c3_4_1, s3_4_1, p77_q4, p20_q4, p10_q4, p01_q4, p00_q4};
  wire [29:0] bank5_q;
  dff #(30) u_bank5 (.clk(clk), .rst_n(rst_n), .d(bank5_d), .q(bank5_q));

  wire p00_q5 = bank5_q[0];
  wire p01_q5 = bank5_q[1];
  wire p10_q5 = bank5_q[2];
  wire p20_q5 = bank5_q[3];
  wire p77_q5 = bank5_q[4];
  wire s3_4_1_q1 = bank5_q[5];
  wire c3_4_1_q1 = bank5_q[6];
  wire s4_4_1_q1 = bank5_q[7];
  wire c4_4_1_q1 = bank5_q[8];
  wire s5_4_1_q1 = bank5_q[9];
  wire c5_4_1_q1 = bank5_q[10];
  wire s6_4_1_q1 = bank5_q[11];
  wire c6_4_1_q1 = bank5_q[12];
  wire s7_4_1_q1 = bank5_q[13];
  wire c7_4_1_q1 = bank5_q[14];
  wire s8_4_1_q1 = bank5_q[15];
  wire c8_4_1_q1 = bank5_q[16];
  wire s9_4_1_q1 = bank5_q[17];
  wire c9_4_1_q1 = bank5_q[18];
  wire s10_4_1_q1 = bank5_q[19];
  wire c10_4_1_q1 = bank5_q[20];
  wire s11_4_1_q1 = bank5_q[21];
  wire c11_4_1_q1 = bank5_q[22];
  wire s12_4_1_q1 = bank5_q[23];
  wire c12_4_1_q1 = bank5_q[24];
  wire s13_4_1_q1 = bank5_q[25];
  wire c13_4_1_q1 = bank5_q[26];
  wire s14_4_1_q1 = bank5_q[27];
  wire c14_4_1_q1 = bank5_q[28];
  wire result_sign_q5 = bank5_q[29];

  // ---------------------------------------------------------------------
  // S6 (comb): final vector-merge addition (14-bit CLA) -- magnitude result
  // ---------------------------------------------------------------------
  wire [14:1] merge_a, merge_b, merge_sum;
  wire merge_cout;

  assign merge_a[1]  = p01_q5;
  assign merge_b[1]  = p10_q5;
  assign merge_a[2]  = p20_q5;
  assign merge_b[2]  = s3_4_1_q1;
  assign merge_a[3]  = c3_4_1_q1;
  assign merge_b[3]  = s4_4_1_q1;
  assign merge_a[4]  = c4_4_1_q1;
  assign merge_b[4]  = s5_4_1_q1;
  assign merge_a[5]  = c5_4_1_q1;
  assign merge_b[5]  = s6_4_1_q1;
  assign merge_a[6]  = c6_4_1_q1;
  assign merge_b[6]  = s7_4_1_q1;
  assign merge_a[7]  = c7_4_1_q1;
  assign merge_b[7]  = s8_4_1_q1;
  assign merge_a[8]  = c8_4_1_q1;
  assign merge_b[8]  = s9_4_1_q1;
  assign merge_a[9]  = c9_4_1_q1;
  assign merge_b[9]  = s10_4_1_q1;
  assign merge_a[10]  = c10_4_1_q1;
  assign merge_b[10]  = s11_4_1_q1;
  assign merge_a[11]  = c11_4_1_q1;
  assign merge_b[11]  = s12_4_1_q1;
  assign merge_a[12]  = c12_4_1_q1;
  assign merge_b[12]  = s13_4_1_q1;
  assign merge_a[13]  = c13_4_1_q1;
  assign merge_b[13]  = s14_4_1_q1;
  assign merge_a[14]  = p77_q5;
  assign merge_b[14]  = c14_4_1_q1;

  cla_adder14 u_final_cla (.a(merge_a), .b(merge_b), .sum(merge_sum), .cout(merge_cout));

  // ---------------------------------------------------------------------
  // Pipeline register bank R6 : magnitude-result bits + result_sign (last hop)
  // ---------------------------------------------------------------------
  wire [16:0] bank6_d = {result_sign_q5, merge_cout, merge_sum[14], merge_sum[13], merge_sum[12], merge_sum[11], merge_sum[10], merge_sum[9], merge_sum[8], merge_sum[7], merge_sum[6], merge_sum[5], merge_sum[4], merge_sum[3], merge_sum[2], merge_sum[1], p00_q5};
  wire [16:0] bank6_q;
  dff #(17) u_bank6 (.clk(clk), .rst_n(rst_n), .d(bank6_d), .q(bank6_q));

  wire p00_q6 = bank6_q[0];
  wire merge_sum_1_q1 = bank6_q[1];
  wire merge_sum_2_q1 = bank6_q[2];
  wire merge_sum_3_q1 = bank6_q[3];
  wire merge_sum_4_q1 = bank6_q[4];
  wire merge_sum_5_q1 = bank6_q[5];
  wire merge_sum_6_q1 = bank6_q[6];
  wire merge_sum_7_q1 = bank6_q[7];
  wire merge_sum_8_q1 = bank6_q[8];
  wire merge_sum_9_q1 = bank6_q[9];
  wire merge_sum_10_q1 = bank6_q[10];
  wire merge_sum_11_q1 = bank6_q[11];
  wire merge_sum_12_q1 = bank6_q[12];
  wire merge_sum_13_q1 = bank6_q[13];
  wire merge_sum_14_q1 = bank6_q[14];
  wire merge_cout_q1 = bank6_q[15];
  wire result_sign_q6 = bank6_q[16];

  // ---------------------------------------------------------------------
  // S7 (comb): conditional two's-complement sign correction
  // ---------------------------------------------------------------------
  wire [15:0] magnitude_result = {merge_cout_q1, merge_sum_14_q1, merge_sum_13_q1, merge_sum_12_q1, merge_sum_11_q1, merge_sum_10_q1, merge_sum_9_q1, merge_sum_8_q1, merge_sum_7_q1, merge_sum_6_q1, merge_sum_5_q1, merge_sum_4_q1, merge_sum_3_q1, merge_sum_2_q1, merge_sum_1_q1, p00_q6};

  wire [15:0] negated_result;
  twos_complement #(16) u_neg_result (.in(magnitude_result), .out(negated_result));

  wire [15:0] final_sum = result_sign_q6 ? negated_result : magnitude_result;

  // ---------------------------------------------------------------------
  // R7 : final, fully-registered output (= sum)
  // ---------------------------------------------------------------------
  wire [15:0] sum_q;
  dff #(16) u_bank7 (.clk(clk), .rst_n(rst_n), .d(final_sum), .q(sum_q));

  assign sum = sum_q;

endmodule


// ============================================================================
// CLA 16-bit adder — one complete pipeline "stage" (combinational adder;
// the register after it is inside the tree stages below)
// ============================================================================
module cla_adder16 (
    input  [15:0] a,
    input  [15:0] b,
    input         cin,
    output [15:0] sum,
    output        cout
);
    // Four 4-bit CLA blocks
    wire bg0,bp0,bg1,bp1,bg2,bp2,bg3,bp3;
    wire c0,c1,c2,c3;

    assign c0 = cin;
    assign c1 = bg0 | (bp0 & c0);
    assign c2 = bg1 | (bp1 & c1);
    assign c3 = bg2 | (bp2 & c2);
    assign cout = bg3 | (bp3 & c3);

    cla_block4 blk0 (.a(a[3:0]),   .b(b[3:0]),   .cin(c0), .sum(sum[3:0]),   .bg(bg0), .bp(bp0));
    cla_block4 blk1 (.a(a[7:4]),   .b(b[7:4]),   .cin(c1), .sum(sum[7:4]),   .bg(bg1), .bp(bp1));
    cla_block4 blk2 (.a(a[11:8]),  .b(b[11:8]),  .cin(c2), .sum(sum[11:8]),  .bg(bg2), .bp(bp2));
    cla_block4 blk3 (.a(a[15:12]), .b(b[15:12]), .cin(c3), .sum(sum[15:12]), .bg(bg3), .bp(bp3));
endmodule


module and_gate(input a, input b, output p);
  assign p = a & b;
endmodule


module full_add(a,b,c,sum,carry);
  input a;
  input b;
  input c;
  
  output sum;
  output carry;
  
  
  assign sum=a^b^c;
  assign carry=(a&b)|(b&c)|(c&a);
  
endmodule


module half_add(a,b,sum,carry);
  
  input a;
  input b;
  
  output sum;
  output carry;
  
  
  assign sum=a^b;
  assign carry=a&b;
endmodule


// Generic D flip-flop with an asynchronous, active-low reset.
// WIDTH lets one instance register an entire bus, so a whole pipeline
// stage's worth of signals can be captured with a single instantiation.
module dff #(
    parameter WIDTH = 1
) (
    input                  clk,
    input                  rst_n,   // asynchronous, active-low
    input  [WIDTH-1:0]     d,
    output reg [WIDTH-1:0] q
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            q <= {WIDTH{1'b0}};
        else
            q <= d;
    end

endmodule


// Computes the two's-complement negation of `in` (i.e. out = ~in + 1).
// Built structurally from half_add cells: inverting every bit and then
// adding the constant 1 is just a "ripple increment by one" of the
// inverted bus, which only ever needs a half adder at each bit position
// (the constant 1 is the initial carry-in; every later bit only ever
// adds an inverted input bit to the carry coming from the bit below).
module twos_complement #(
    parameter WIDTH = 8
) (
    input  [WIDTH-1:0] in,
    output [WIDTH-1:0] out
);

    wire [WIDTH-1:0] inverted;
    /* verilator lint_off UNUSEDSIGNAL */
    wire [WIDTH-1:0] carry;
    /* verilator lint_on UNUSEDSIGNAL */

    assign inverted = ~in;

    // bit 0: add the constant '1' (the "start negating" carry-in)
    half_add u_inc0 (.a(inverted[0]), .b(1'b1), .sum(out[0]), .carry(carry[0]));

    // remaining bits: ripple the carry forward
    genvar i;
    generate
        for (i = 1; i < WIDTH; i = i + 1) begin : inc_chain
            half_add u_inc (.a(inverted[i]), .b(carry[i-1]), .sum(out[i]), .carry(carry[i]));
        end
    endgenerate

endmodule


// 14-bit carry-lookahead adder for the final vector-merge stage, built as 4+4+4+2
// lookahead blocks. The carry between blocks is found from block-generate/propagate
// signals in one extra level of logic, instead of rippling through all 14 bit positions.
module cla_adder14(
    input  [14:1] a,
    input  [14:1] b,
    output [14:1] sum,
    output        cout
);
  wire bg0, bp0, bg1, bp1, bg2, bp2, bg3, bp3;
  wire cin0, cin1, cin2, cin3;

  assign cin0 = 1'b0;               // no carry into column-weight 1
  assign cin1 = bg0 | (bp0 & cin0);
  assign cin2 = bg1 | (bp1 & cin1);
  assign cin3 = bg2 | (bp2 & cin2);
  assign cout = bg3 | (bp3 & cin3);

  cla_block4 blk0 (.a(a[4:1]),   .b(b[4:1]),   .cin(cin0), .sum(sum[4:1]),   .bg(bg0), .bp(bp0));
  cla_block4 blk1 (.a(a[8:5]),   .b(b[8:5]),   .cin(cin1), .sum(sum[8:5]),   .bg(bg1), .bp(bp1));
  cla_block4 blk2 (.a(a[12:9]),  .b(b[12:9]),  .cin(cin2), .sum(sum[12:9]),  .bg(bg2), .bp(bp2));
  cla_block2 blk3 (.a(a[14:13]), .b(b[14:13]), .cin(cin3), .sum(sum[14:13]), .bg(bg3), .bp(bp3));
endmodule


module cla_block4(
    input  [3:0] a,
    input  [3:0] b,
    input        cin,
    output [3:0] sum,
    output       bg,   // block generate: this block makes a carry even if cin = 0
    output       bp    // block propagate: this block passes an incoming carry straight through
);
  wire [3:0] g, p;
  wire c1, c2, c3;

  assign g = a & b;
  assign p = a ^ b;

  assign c1 = g[0] | (p[0] & cin);
  assign c2 = g[1] | (p[1] & g[0]) | (p[1] & p[0] & cin);
  assign c3 = g[2] | (p[2] & g[1]) | (p[2] & p[1] & g[0]) | (p[2] & p[1] & p[0] & cin);

  assign sum[0] = p[0] ^ cin;
  assign sum[1] = p[1] ^ c1;
  assign sum[2] = p[2] ^ c2;
  assign sum[3] = p[3] ^ c3;

  assign bg = g[3] | (p[3] & g[2]) | (p[3] & p[2] & g[1]) | (p[3] & p[2] & p[1] & g[0]);
  assign bp = p[3] & p[2] & p[1] & p[0];
endmodule


// Same idea as cla_block4, just for the 2-bit tail block (14 isn't a multiple of 4).
module cla_block2(
    input  [1:0] a,
    input  [1:0] b,
    input        cin,
    output [1:0] sum,
    output       bg,
    output       bp
);
  wire [1:0] g, p;
  wire c1;

  assign g = a & b;
  assign p = a ^ b;

  assign c1 = g[0] | (p[0] & cin);

  assign sum[0] = p[0] ^ cin;
  assign sum[1] = p[1] ^ c1;

  assign bg = g[1] | (p[1] & g[0]);
  assign bp = p[1] & p[0];
endmodule

