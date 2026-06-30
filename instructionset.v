module Memory(
    input clk,
    input [31:0] mem_addr,
    output [31:0] mem_rdata,
    input mem_rstrb // goes high when processor wants to read
    input [31:0] mem_wdata,
    input [3:0] mem_wmask // how many bytes to write, in a 4 byte word
);


reg [31:0] MEM [0:1535]; //6KB RAM


/// IDK WHAT THIS MEANS LOWKEY

`ifdef BENCH
   localparam slow_bit=12;
`else
   localparam slow_bit=17;
`endif

   // Memory-mapped IO in IO page, 1-hot addressing in word address.
   localparam IO_LEDS_bit      = 0;  // W five leds
   localparam IO_UART_DAT_bit  = 1;  // W data to send (8 bits)
   localparam IO_UART_CNTL_bit = 2;  // R status. bit 9: busy sending

   // Converts an IO_xxx_bit constant into an offset in IO page.
   function [31:0] IO_BIT_TO_OFFSET;
      input [31:0] bitid;
      begin
	 IO_BIT_TO_OFFSET = 1 << (bitid + 2);
      end
   endfunction

`include "riscv_assembly.v"
   integer    L0_      = 12;
   integer    L1_      = 20;
   integer    L2_      = 52;
   integer    wait_    = 104;
   integer    wait_L0_ = 112;
   integer    putc_    = 124;
   integer    putc_L0_ = 132;

   initial begin
      LI(sp,32'h1800);   // End of RAM, 6kB
      LI(gp,32'h400000); // IO page

   Label(L0_);

      // Count from 0 to 15 on the LEDs
      LI(s0,16); // upper bound of loop
      LI(a0,0);
   Label(L1_);
      SW(a0,gp,IO_BIT_TO_OFFSET(IO_LEDS_bit));
      CALL(LabelRef(wait_));
      ADDI(a0,a0,1);
      BNE(a0,s0,LabelRef(L1_));

      // Send abcdef...xyz to the UART
      LI(s0,26); // upper bound of loop
      LI(a0,"a");
      LI(s1,0);
   Label(L2_);
      CALL(LabelRef(putc_));
      ADDI(a0,a0,1);
      ADDI(s1,s1,1);
      BNE(s1,s0,LabelRef(L2_));

      // CR;LF
      LI(a0,13);
      CALL(LabelRef(putc_));
      LI(a0,10);
      CALL(LabelRef(putc_));

      J(LabelRef(L0_));

      EBREAK(); // I systematically keep it before functions
                // in case I decide to remove the loop...

   Label(wait_);
      LI(t0,1);
      SLLI(t0,t0,slow_bit);
   Label(wait_L0_);
      ADDI(t0,t0,-1);
      BNEZ(t0,LabelRef(wait_L0_));
      RET();

   Label(putc_);
      // Send character to UART
      SW(a0,gp,IO_BIT_TO_OFFSET(IO_UART_DAT_bit));
      // Read UART status, and loop until bit 9 (busy sending)
      // is zero.
      LI(t0,1<<9);
   Label(putc_L0_);
      LW(t1,gp,IO_BIT_TO_OFFSET(IO_UART_CNTL_bit));
      AND(t1,t1,t0);
      BNEZ(t1,LabelRef(putc_L0_));
      RET();

      endASM();
   end

/// IDK WHAT THIS MEANS LOWKEY

wire [29:0] word_addr = mem_addr[31:2];

always @(posedge clk) begin
    if (mem_rstrb) begin
        mem_rdata <= MEM[mem_addr[31:2]]; //31:2 for byte adress
    end
    if(mem_wmask[0]) MEM[word_addr][ 7:0 ] <= mem_wdata[ 7:0 ];
    if(mem_wmask[1]) MEM[word_addr][15:8 ] <= mem_wdata[15:8 ];
    if(mem_wmask[2]) MEM[word_addr][23:16] <= mem_wdata[23:16];
    if(mem_wmask[3]) MEM[word_addr][31:24] <= mem_wdata[31:24];
end

endmodule

module Processor(
    input clk,
    input resetn,
    output [31:0] mem_addr,
    input [31:0] mem_rdata,
    output mem_rstrb,
    output [31:0] mem_wdata,
    output [3:0] mem_wmask,
);

reg [31:0] PC = 0;
reg [31:0] instr;   // current instructions
// instructions grouped, all of these reperesnt the 7:0 opcode

wire isALUreg = (instr[6:0] == 7'b0110011); // rd <- rs1 OP rs2
wire isALUimm = (instr[6:0] == 7'b0010011); // rd <- rs1 OP Iimm
wire isBranch = (instr[6:0] == 7'b1100011); // if(rs1 OP rs2) PC <- PC + Bimm
wire isLoad = (instr[6:0] == 7'b0000011); // rd <- mem[rs1+Iimm]
wire isStore = (instr[6:0] == 7'b0100011); // mem[rs1+Simm] <- rs2
wire isLUI = (instr[6:0] == 7'b0110111); // rd <- Uimm
wire isAUIPC = (instr[6:0] == 7'b0010111); // rd <- PC + Uimm
wire isSYSTEM = (instr[6:0] == 7'1110011); 
wire isJAL = (instr[6:0] == 7'1101111); // rd <- PC+4; PC<-PC+Jimm
wire isJALR =  (instr[6:0] == 7'b1100111); // rd <- PC+4; PC<-rs1+Iimm


// types
wire [31:0] Iimm={{21{instr[31]}}, instr[30:20]};
wire [31:0] Simm={{21{instr[31]}}, instr[30:25], instr[11:7]};
wire [31:0] Bimm={{20{instr[31]}}, instr[7],instr[30:25],instr[11:8],1'b0};
wire [31:0] Uimm={instr[31:12], {12{1'b0}}};
wire [31:0] Uimm={{12{instr[31]}}, instr[19:12], instr[20], instr[30:21],1'b0};


// getting rs1, rs2, rd
wire [4:0] rs1Id = instr[19:15];
wire [4:0] rs2Id = instr[24:20];
wire [4:0] rdIdId  = instr[11:7];

// function codes
wire [2:0] funct3 = instr[14:12];
wire [6:0] funct7 = instr[31:25];

// The registers bank
   reg [31:0] RegisterBank [0:31];
   reg [31:0] rs1; // value of source
   reg [31:0] rs2; //  registers.
   wire [31:0] writeBackData; // data to be written to rd
   wire writeBackEn;   // asserted if data should be written to rd

`ifdef BENCH
   integer     i;
   initial begin
      for(i=0; i<32; ++i) begin
	 RegisterBank[i] = 0;
      end
   end
`endif

// The ALU

wire aluIn1 = rs1;
wire aluIn2 = isAlureg|isBranch ? rs2 : Iimm;

reg [4:0] shamt = isALureg ? rs2[4:0] : instr[24:20]; // shift amount




// optimization
wire [31:0] aluPlus = aluIn1 + aluIn2;
wire [32:0] aluMinus =  {1'b0,aluIn1} + {1'b1, ~aluIn2}+ 33'b1; 

wire EQ = (aluMinus == 0);
wire LTU = (aluMinus[32]);
wire LT = (aluIn1[31] ^ aluIn2[31]) ? aluin1[31] : aluMinus[32];

function [31:0] flip32;
    input [31:0] x;
    flip32 = {x[ 0], x[ 1], x[ 2], x[ 3], x[ 4], x[ 5], x[ 6], x[ 7], 
    x[ 8], x[ 9], x[10], x[11], x[12], x[13], x[14], x[15], 
    x[16], x[17], x[18], x[19], x[20], x[21], x[22], x[23],
    x[24], x[25], x[26], x[27], x[28], x[29], x[30], x[31]};
endfunction

wire [31:0] shifter_in = (funct3 == 3'b001) ? flip32(aluIn1) : aluIn1;

/* verilator lint_off WIDTH */
wire [31:0] shifter = 
            $signed({instr[30] & aluIn1[31], shifter_in}) >>> aluIn2[4:0];
   /* verilator lint_on WIDTH */
wire [31:0] leftshift = flip32(shifter);


// ADD/SUB/ADDI
reg [31:0] aluOut;
always @(*) begin
    case (funct3)
        3'b000: aluOut = (funct7[5] & instr[5]) ? aluMinus[31:0] : aluPlus;
        3'b001: aluOut = leftshift;
        3'b010: aluOut = {31'b0, LT};
        3'b011: aluOut = {31'b0, LTU};
        3'b100: aluOut = aluIn1 ^ aluIn2;
        3'b101: aluOut = shifter;
        3'b110: aluOut = aluIn1 | aluIn2;
        3'b111: aluOut = aluIn1 & aluIn2;
    endcase
end

// Jumps
reg takeBranch;

always @(*) begin
    case (funct3)
        3'b000: takeBranch = EQ;
        3'b001: takeBranch = !EQ;
        3'b010: takeBranch = LT; // signed
        3'b101: takeBranch = !LT; // signed
        3'b110: takeBranch = LTU;  
        3'b111: takeBranch = !LTU; 
        default: takeBranch = 1'b0;
    endcase
end


// Next PC computation
// branch->PC+Bimm    AUIPC->PC+Uimm    JAL->PC+Jimm

wire [31:0] PCplusImm = PC + ( instr[3] ? Jimm[31:0] :
				        instr[4] ? Uimm[31:0] :
				        Bimm[31:0] );

wire [31:0] PCplus4 = PC+4;

// register writeback
assign [31:0] writeBackData = (isJAL || isJALR) ? PCplus4 :
			                isLUI         ? Uimm :
			                isAUIPC       ? PCplusImm : 
                            isLoad          ? LOAD_data :
			                aluOut;

wire [31:0] nextPC = ((isBranch && takeBranch) || isJAL) ? PCplusImm   :
	                                  isJALR   ? {aluPlus[31:1],1'b0} :
	                                             PCplus4;






wire [31:0] loadstore_addr = rs1 + (isStore ? Simm : Iimm);

// LOAD 
wire mem_byteAccess     = funct3[1:0] == 2'b00; // check which byte adress, 
wire mem_halfwordAccess = funct3[1:0] == 2'b01; // check which halfword adress

wire [15:0] LOAD_halfword = loadstore_addr[1] ? mem_rdata[31:16] : mem_rdata[15:0]; // First select either upper word or lower halfword

wire  [7:0] LOAD_byte = loadstore_addr[0] ? LOAD_halfword[15:8] : LOAD_halfword[7:0]; // Then select either upper byte or lower byte

wire LOAD_sign = !funct3[2] & (mem_byteAccess ? LOAD_byte[7] : LOAD_halfword[15]); // Check if the load is signed or unsigned, if signed then check the sign bit of the byte or halfword

wire [31:0] LOAD_data =
    mem_byteAccess ? {{24{LOAD_sign}}, LOAD_byte}     :
    mem_halfwordAccess ? {{16{LOAD_sign}}, LOAD_halfword} :
                        mem_rdata     ;

// STORE
// idk why he decided to duplicate rs2, this is becasue we take the whole of wdata, 
// and we can write to any byte word if needed
// ex: store x44 into 0100, changes the whole thing into x44444444, so x11223344 = x11443344
// only if we are going to store halfword, then we have to take the other word, x3344, so it becomes x33443344 etc...

assign mem_wdata[ 7: 0] = rs2[7:0];
assign mem_wdata[15: 8] = loadstore_addr[0] ? rs2[7:0]  : rs2[15: 8];
assign mem_wdata[23:16] = loadstore_addr[1] ? rs2[7:0]  : rs2[23:16];
assign mem_wdata[31:24] = loadstore_addr[0] ? rs2[7:0]  :
                loadstore_addr[1] ? rs2[15:8] : rs2[31:24];

wire [3:0] STORE_wmask =
        mem_byteAccess      ?
            (loadstore_addr[1] ?
                (loadstore_addr[0] ? 4'b1000 : 4'b0100) :
                (loadstore_addr[0] ? 4'b0010 : 4'b0001)
                ) :
        mem_halfwordAccess ?
            (loadstore_addr[1] ? 4'b1100 : 4'b0011) :
            4'b1111;    


localparam FETCH_INSTR=0;
localparam WAIT_INSTR=1;
localparam FETCH_REGS=2;
localparam EXECUTE=3;
localparam LOAD=4;
localparam WAIT_DATA=5;
localparam STORE=6;

reg [2:0] state = FETCH_INSTR;


always @(posedge clk) begin

    if(!resetn) begin
        PC    <= 0;
        state <= FETCH_INSTR;
    end else begin

    //write back

    if (writeBackEn && (rdId != 0)) begin
        RegisterBank[rdId] = writeBackData;
    end

    // state machine
    case (state)
        FETCH_INSTR: begin
            state <= WAIT_INSTR;
            
        end
        WAIT_INSTR: begin
            instr <= mem_rdata;
            state <= FETCH_REGS;
        end
        FETCH_REGS: begin
            rs1 <= RegisterBank[rs1Id];
            rs2 <= RegisterBank[rs2Id];
            state <= EXECUTE;
        end
        EXECUTE: begin
            if (!isSYSTEM)  begin
            PC <= nextPC;
            end
            state <=    isLoad ? LOAD : 
                        isStore ? STORE:
                        FETCH_INSTR;

            `ifdef BENCH
	            if(isSYSTEM) $finish();
            `endif  
        end
        LOAD: begin
	        state <= WAIT_DATA;
	    end
	    WAIT_DATA: begin
	        state <= FETCH_INSTR;
        end
        STORE: begin
            state <= FETCH_INSTR;
        end
    endcase
    end 
end

wire writeBackEn = (state == EXECUTE && !isBranch && !isStore) || (state == WAIT_DATA);

assign mem_addr = (state == WAIT_INSTR || state == FETCH_INSTR) ? PC : loadstore_addr ;
assign mem_rstrb = (state == FETCH_INSTR || state == LOAD);
assign mem_wmask = {4{(state == STORE)}} & STORE_wmask;

endmodule



module SOC(
    input CLK,
    input RESET,
    output reg [4:0] LEDS,
    input RXD,
    output TXD,
)
wire clk;
wire resetn;

wire [31:0] mem_addr;
wire [31:0] mem_rdata;
wire mem_rstrb;
wire [31:0] mem_wdata;
wire [3:0] mem_wmask;



Processor CPU(
    .clk(clk),
    .resetn(resetn),
    .mem_addr(mem_addr),
    .mem_rdata(mem_rdata),
    .mem_rstrb(mem_rstrb),
    .mem_wdata(mem_wdata),
    .mem_wmask(mem_wmask),
);

wire [31:0] RAM_rdata;
wire [29:0] mem_wordaddr = mem_addr[31:2];
wire isIO = mem_addr[22];
wire isRAM = !isIO;
wire mem_wstrb = |mem_wmask;

Memory RAM(
    .clk(clk),
    .mem_addr(mem_addr),
    .mem_rdata(RAM_rdata),
    .mem_rstrb(isRAM & mem_rstrb),
    .mem_wdata(mem_wdata),
    .mem_wmask({4{isRAM}}&mem_wmask)
);

localparam IO_LEDS_bit      = 0;  // W five leds
localparam IO_UART_DAT_bit  = 1;  // W data to send (8 bits)
localparam IO_UART_CNTL_bit = 2;  // R status. bit 9: busy sending

always @(posedge clk) begin
    if(isIO & mem_wstrb & mem_wordaddr[IO_LEDS_bit]) begin
    LEDS <= mem_wdata;
    end
end

wire uart_valid = isIO & mem_wstrb & mem_wordaddr[IO_UART_DAT_bit];
wire uart_ready;


corescore_emitter_uart #(
    .clk_freq_hz(`CPU_FREQ*1000000)
) UART(
    .i_clk(clk),
    .i_rst(!resetn),
    .i_data(mem_wdata[7:0]),
    .i_valid(uart_valid),
    .o_ready(uart_ready),
    .o_uart_tx(TXD)
);

wire [31:0] IO_rdata =
        mem_wordaddr[IO_UART_CNTL_bit] ? { 22'b0, !uart_ready, 9'b0}
                                        : 32'b0;

assign mem_rdata = isRAM ? RAM_rdata :
                        IO_rdata ;


`ifdef BENCH
   always @(posedge clk) begin
      if(uart_valid) begin
	 $write("%c", mem_wdata[7:0] );
	 $fflush(32'h8000_0001);
      end
   end
`endif

// TAKE THIS MODULE FROM FemtoRV

Clockworks CW (
     .CLK(CLK),
     .RESET(RESET),
     .clk(clk),
     .resetn(resetn)
   );

   assign TXD  = 1'b0;  // not used for now
endmodule
