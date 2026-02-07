/**
 * gol_engine.v — Game of Life update FSM. 256×256 toroidal, 32 species, double-buffered.
 * States: INIT (seed both banks), READ_CENTER, READ_NEIGHBORS (8), APPLY_RULES, ADVANCE, IDLE.
 * Swap buffers only on video_sof. 1-cycle RAM read latency pipelined.
 */
module gol_engine (
    input  wire        clk,
    input  wire        rst,
    input  wire        video_sof,
    input  wire [4:0]  dout_bank0,
    input  wire [4:0]  dout_bank1,
    output reg         ram_select,   // 0 = display bank0, 1 = display bank1 → update bank = ~ram_select
    output wire        init_done,    // 0 during INIT (blank display), 1 after
    output wire [3:0]  state_out,    // FSM state for debug (0=INIT,1=READ_CENTER,2=READ_NEIGH,3=APPLY,4=ADVANCE,5=IDLE)
    output wire [15:0] gen_count,   // generations completed (increments each frame after swap)
    output wire [511:0] pop_count,  // pop_count[16*i+15:16*i] = count of species i (0-31)
    output reg [15:0]  addr,
    output reg         we0,
    output reg         we1,
    output reg [4:0]   din
);
    // Read from DISPLAY bank (current frame); write next frame to the other bank (dual-port allows both)
    wire [4:0] dout_src = ram_select ? dout_bank1 : dout_bank0;

    localparam [3:0] S_INIT         = 4'd0,
                     S_READ_CENTER  = 4'd1,
                     S_READ_NEIGH   = 4'd2,
                     S_APPLY_RULES  = 4'd3,
                     S_ADVANCE      = 4'd4,
                     S_IDLE         = 4'd5;

    reg [3:0]  state, next_state;
    reg [15:0] cell_index;       // 0..65535, row-major: {y[7:0], x[7:0]}
    reg [7:0]  x, y;
    reg [2:0]  neighbor_idx;     // 0..7
    reg [1:0]  init_phase;       // 0 or 1 for dual-write during INIT
    reg [15:0] init_addr;
    reg [15:0] gen_count_r;      // generations completed
    reg [15:0] pop_count_r [0:31];  // population per species (0-31)

    // LFSR for random seed (16-bit)
    reg [15:0] lfsr;

    // Pipeline: center cell (from READ_CENTER, used in APPLY_RULES)
    reg [4:0] center_cell;
    // Neighbor accumulation
    reg [3:0] alive_count;
    reg [4:0] species_a, species_b, species_c;  // up to 3 alive species for birth majority
    reg [1:0] species_count;     // how many of a,b,c we've stored

    // Neighbor offsets: n0=(x-1,y-1), n1=(x,y-1), n2=(x+1,y-1), n3=(x-1,y), n4=(x+1,y), n5=(x-1,y+1), n6=(x,y+1), n7=(x+1,y+1) — 8-bit wrap
    wire [7:0] x_prev = x - 8'd1;
    wire [7:0] x_next = x + 8'd1;
    wire [7:0] y_prev = y - 8'd1;
    wire [7:0] y_next = y + 8'd1;

    wire [15:0] neighbor_addr [0:7];
    assign neighbor_addr[0] = {y_prev, x_prev};
    assign neighbor_addr[1] = {y_prev, x};
    assign neighbor_addr[2] = {y_prev, x_next};
    assign neighbor_addr[3] = {y, x_prev};
    assign neighbor_addr[4] = {y, x_next};
    assign neighbor_addr[5] = {y_next, x_prev};
    assign neighbor_addr[6] = {y_next, x};
    assign neighbor_addr[7] = {y_next, x_next};

    assign init_done  = (state != S_INIT);
    assign state_out  = state;
    assign gen_count  = gen_count_r;
    assign pop_count  = { pop_count_r[31], pop_count_r[30], pop_count_r[29], pop_count_r[28],
                          pop_count_r[27], pop_count_r[26], pop_count_r[25], pop_count_r[24],
                          pop_count_r[23], pop_count_r[22], pop_count_r[21], pop_count_r[20],
                          pop_count_r[19], pop_count_r[18], pop_count_r[17], pop_count_r[16],
                          pop_count_r[15], pop_count_r[14], pop_count_r[13], pop_count_r[12],
                          pop_count_r[11], pop_count_r[10], pop_count_r[9], pop_count_r[8],
                          pop_count_r[7], pop_count_r[6], pop_count_r[5], pop_count_r[4],
                          pop_count_r[3], pop_count_r[2], pop_count_r[1], pop_count_r[0] };

    // Next cell state from Conway + species rules
    wire center_alive = (center_cell != 5'd0);
    wire birth  = (alive_count == 4'd3) && !center_alive;
    wire survive = (alive_count == 4'd2 || alive_count == 4'd3) && center_alive;
    wire [4:0] birth_species;  // majority of species_a, species_b, species_c or tiebreak
    wire [4:0] new_cell = birth  ? birth_species :
                          survive ? center_cell : 5'd0;

    // Majority of 3 species (1..31): two same -> that one; else tiebreak to first
    assign birth_species = (species_a == species_b || species_a == species_c) ? species_a :
                           (species_b == species_c) ? species_b : species_a;

    always @(posedge clk) begin
        if (rst) begin
            state      <= S_INIT;
            ram_select <= 0;
            cell_index <= 0;
            addr       <= 0;
            we0        <= 0;
            we1        <= 0;
            din        <= 0;
            init_phase  <= 0;
            init_addr   <= 0;
            gen_count_r <= 16'd0;
            lfsr        <= 16'hACE1;
            center_cell   <= 0;
            alive_count   <= 0;
            species_a     <= 0;
            species_b     <= 0;
            species_c     <= 0;
            species_count <= 0;
            neighbor_idx  <= 0;
            pop_count_r[0]<=0; pop_count_r[1]<=0; pop_count_r[2]<=0; pop_count_r[3]<=0;
            pop_count_r[4]<=0; pop_count_r[5]<=0; pop_count_r[6]<=0; pop_count_r[7]<=0;
            pop_count_r[8]<=0; pop_count_r[9]<=0; pop_count_r[10]<=0; pop_count_r[11]<=0;
            pop_count_r[12]<=0; pop_count_r[13]<=0; pop_count_r[14]<=0; pop_count_r[15]<=0;
            pop_count_r[16]<=0; pop_count_r[17]<=0; pop_count_r[18]<=0; pop_count_r[19]<=0;
            pop_count_r[20]<=0; pop_count_r[21]<=0; pop_count_r[22]<=0; pop_count_r[23]<=0;
            pop_count_r[24]<=0; pop_count_r[25]<=0; pop_count_r[26]<=0; pop_count_r[27]<=0;
            pop_count_r[28]<=0; pop_count_r[29]<=0; pop_count_r[30]<=0; pop_count_r[31]<=0;
        end else begin
            case (state)
                S_INIT: begin
                    addr <= init_addr;
                    din  <= (lfsr[0] == 1'b0) ? ((lfsr[4:0] == 5'd0) ? 5'd1 : lfsr[4:0]) : 5'd0;  // ~50% alive, species 1..31
                    if (init_phase == 0) begin
                        we0 <= 1;
                        we1 <= 0;
                        init_phase <= 1;
                    end else begin
                        we0 <= 0;
                        we1 <= 1;
                        init_phase <= 0;
                        lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[14] ^ lfsr[12] ^ lfsr[3]};
                        if (init_addr == 16'd65535) begin
                            state <= S_IDLE;
                            we1   <= 0;
                        end else
                            init_addr <= init_addr + 16'd1;
                    end
                end

                S_IDLE: begin
                    we0 <= 0;
                    we1 <= 0;
                    if (video_sof) begin
                        ram_select   <= ~ram_select;
                        gen_count_r  <= gen_count_r + 16'd1;
                        cell_index   <= 0;
                        x            <= 0;
                        y            <= 0;
                        state        <= S_READ_CENTER;
                        pop_count_r[0]<=0; pop_count_r[1]<=0; pop_count_r[2]<=0; pop_count_r[3]<=0;
                        pop_count_r[4]<=0; pop_count_r[5]<=0; pop_count_r[6]<=0; pop_count_r[7]<=0;
                        pop_count_r[8]<=0; pop_count_r[9]<=0; pop_count_r[10]<=0; pop_count_r[11]<=0;
                        pop_count_r[12]<=0; pop_count_r[13]<=0; pop_count_r[14]<=0; pop_count_r[15]<=0;
                        pop_count_r[16]<=0; pop_count_r[17]<=0; pop_count_r[18]<=0; pop_count_r[19]<=0;
                        pop_count_r[20]<=0; pop_count_r[21]<=0; pop_count_r[22]<=0; pop_count_r[23]<=0;
                        pop_count_r[24]<=0; pop_count_r[25]<=0; pop_count_r[26]<=0; pop_count_r[27]<=0;
                        pop_count_r[28]<=0; pop_count_r[29]<=0; pop_count_r[30]<=0; pop_count_r[31]<=0;
                    end
                end

                S_READ_CENTER: begin
                    we0 <= 0;
                    we1 <= 0;
                    addr <= {y, x};
                    // center value arrives next cycle (1-cycle RAM latency); don't latch dout_src here
                    alive_count <= 0;
                    species_a   <= 0;
                    species_b   <= 0;
                    species_c   <= 0;
                    species_count <= 0;
                    neighbor_idx <= 0;
                    state <= S_READ_NEIGH;
                end

                S_READ_NEIGH: begin
                    we0 <= 0;
                    we1 <= 0;
                    // dout_src this cycle: center when neighbor_idx==0, else previous neighbor
                    if (neighbor_idx == 3'd0)
                        center_cell <= dout_src;
                    else if (neighbor_idx > 3'd0) begin
                        if (dout_src != 5'd0) begin
                            alive_count <= alive_count + 4'd1;
                            if (species_count == 2'd0) species_a <= dout_src;
                            else if (species_count == 2'd1) species_b <= dout_src;
                            else if (species_count == 2'd2) species_c <= dout_src;
                            if (species_count < 2'd3) species_count <= species_count + 2'd1;
                        end
                    end
                    addr <= neighbor_addr[neighbor_idx];
                    if (neighbor_idx == 3'd7) begin
                        state <= S_APPLY_RULES;
                    end else
                        neighbor_idx <= neighbor_idx + 3'd1;
                end

                S_APPLY_RULES: begin
                    // Last neighbor's dout_src arrives this cycle; add it
                    if (dout_src != 5'd0) begin
                        alive_count <= alive_count + 4'd1;
                        if (species_count == 2'd0) species_a <= dout_src;
                        else if (species_count == 2'd1) species_b <= dout_src;
                        else if (species_count == 2'd2) species_c <= dout_src;
                        if (species_count < 2'd3) species_count <= species_count + 2'd1;
                    end
                    // Count population for center_cell
                    pop_count_r[center_cell] <= pop_count_r[center_cell] + 16'd1;
                    state <= S_ADVANCE;
                end

                S_ADVANCE: begin
                    // Write EVERY cell to update bank (skip-write corrupts double buffer)
                    addr <= {y, x};
                    din  <= new_cell;
                    we0  <= ram_select;
                    we1  <= ~ram_select;
                    if (cell_index == 16'd65535) begin
                        state <= S_IDLE;
                    end else begin
                        cell_index <= cell_index + 16'd1;
                        if (x == 8'd255) begin
                            x <= 8'd0;
                            y <= y + 8'd1;
                        end else
                            x <= x + 8'd1;
                        state <= S_READ_CENTER;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
