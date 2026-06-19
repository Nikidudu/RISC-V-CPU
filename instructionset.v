module instructions(

);

reg [31:0] instr;   // current instructions
reg [31:0] MEM [0:255];

// instructions grouped, all of these reperesnt the 7:0 opcode

wire isALUreg = {instr[6:0] == 7'b0110011}; // rd <- rs1 OP rs2
wire isALUimm = {instr[6:0] == 7'b0010011}; // rd <- rs1 OP Iimm
wire isBranch = {instr[6:0] == 7'b1100011}; // if(rs1 OP rs2) PC <- PC + Bimm
wire isLoad = {instr[6:0] == 7'b0000011}; // rd <- mem[rs1+Iimm]
wire isStore = {instr[6:0] == 7'b0100011}; // mem[rs1+Simm] <- rs2
wire isLUI = {instr[6:0] == 7'b0110111}; // rd <- Uimm
wire isAUIPC = {instr[6:0] == 7'b0010111}; // rd <- PC + Uimm
wire isSYSTEM = {instr[6:0] == 7'1110011}; 
wire isJAL = {instr[6:0] == 7'1101111}; // rd <- PC+4; PC<-PC+Jimm
wire isJALR =  (instr[6:0] == 7'b1100111); // rd <- PC+4; PC<-rs1+Iimm

// getting rs1, rs2, rd

wire [4:0] rs1Id = instr[19:15];
wire [4:0] rs2Id = instr[24:20];
wire [4:0] rdIdId  = instr[11:7];

// function codes
wire [2:0] funct3 = instr[14:12];
wire [6:0] funct7 = instr[31:25];


// types
wire [31:0] Iimm={{21{instr[31]}}, instr[30:20]};
wire [31:0] Simm={{21{instr[31]}}, instr[30:25], instr[11:7]};
wire [31:0] Bimm={{20{instr[31]}}, instr[7],instr[30:25],instr[11:8],1'b0};
wire [31:0] Uimm={instr[31:12], {12{1'b0}}};
wire [31:0] Uimm={{12{instr[31]}}, instr[19:12], instr[20], instr[30:21],1'b0};


// The ALU

wire aluIn1 = rs1;
wire aluIn2 = isAlureg ? rs2 : Iimm;
reg [31:0] aluOut;
reg [4:0] shamt = isALureg ? rs2[4:0] : instr[24:20];

always @(*) begin
    case (funct3)
        3'b000: aluOut = (funct7[5] & instr[5]) ? (aluIn1 - aluIn2) : (aluIn1 + aluIn2);
        3'b001: aluOut = aluIn1 << shamt;
        3'b010: aluOut = ($signed(aluIn1) < $signed(aluIn2));
        3'b011: aluOut = aluIn1 < aluIn2;
        3'b100: aluOut = aluIn1 ^ aluIn2;
        3'b101: aluOut = funct7[5] ? ($signed(aluIn1) >>> shamt): (aluIn1 >> shamt);
        3'b110: aluOut = aluIn1 | aluIn2;
        3'b111: aluOut = aluIn1 & aluIn2;
    endcase
end

// Jumps
reg takebranch;

always @(*) begin
    case (funct3)
        3'b000: takebranch = (rs1 == rs2);
        3'b001: takebranch = (rs1 != rs2);
        3'b010: takebranch = ($signed(rs1) < $signed(rs2)); // signed
        3'b101: takebranch = ($signed(rs1) >= signed(rs2)); // signed
        3'b110: takebranch = (rs1 < rs2);  
        3'b111: takebranch = (rs1 >= rs2); 

    endcase
end


// decoding



wire [31:0] writeBackData = (isJAL || isJALR) ? (PC+4): aluout;
wire writeBackEn = (state == EXECUTE && 
                    (
                    isAlureg || 
                    isALUimm ||
                    isJAL ||
                    is JALR ||
                    )
                        );
wire nextPC =   isJAL ? PC + Jimm : 
                isJALR ? rs1 + Iimm : 
                PC + 4;


reg [31:0] RegisterBank [0:31];
localparam FETCH_INSTR=0;
localparam FETCH_REGS=1;
localparam EXECUTE=2;
reg [1:0] state = FETCH_INSTR;


always @(posedge clk) begin

    //write back

    if (writeBackEn && (rdId != 0)) begin
        RegisterBank[rdId] = writeBackData;
    end




    // state machine
    case (state)
        FETCH_INSTR: begin
            instr <= MEM[PC[31:2]];
            state <= FETCH_REGS;
        end
        FETCH_REGS: begin
            rs1 <= RegisterBank[rs1Id];
            rs2 <= RegisterBank[rs2Id];
            state <= EXECUTE;
        end
        EXECUTE: begin
            PC <= nextPC;
            state <= FETCH_INSTR;
        end
    endcase

end



endmodule



