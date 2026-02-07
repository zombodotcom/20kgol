/**
 * gol_engine.v — Game of Life update FSM. 256×256 toroidal, 7 species, double-buffered.
 * States: INIT (seed both banks), READ_CENTER, READ_NEIGHBORS (8), APPLY_RULES, ADVANCE, IDLE.
 * Swap buffers only on video_sof. 1-cycle RAM read latency pipelined.
 */
module gol_engine (
    input  wire        clk,
    input  wire        rst,
    input  wire        video_sof,
    input  wire [3:0]  dout_bank0,
    input  wire [3:0]  dout_bank1,
    output reg         ram_select,   // 0 = display bank0, 1 = display bank1 → update bank = ~ram_select
    output wire        init_done,    // 0 during INIT (blank display), 1 after
    output reg [15:0]  addr,
    output reg         we0,
    output reg         we1,
    output reg [3:0]   din
);
    // Source bank = update bank (we read from the bank we're updating)
    wire [3:0] dout_src = ram_select ? dout_bank0 : dout_bank1;

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

    // LFSR for random seed (16-bit)
    reg [15:0] lfsr;

    // Pipeline: center cell (from READ_CENTER, used in APPLY_RULES)
    reg [3:0] center_cell;
    // Neighbor accumulation
    reg [3:0] alive_count;
    reg [3:0] species_a, species_b, species_c;  // up to 3 alive species for birth majority
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

    assign init_done = (state != S_INIT);

    // Next cell state from Conway + species rules
    wire center_alive = (center_cell != 4'd0);
    wire birth  = (alive_count == 4'd3) && !center_alive;
    wire survive = (alive_count == 4'd2 || alive_count == 4'd3) && center_alive;
    wire [3:0] birth_species;  // majority of species_a, species_b, species_c or tiebreak
    wire [3:0] new_cell = birth  ? birth_species :
                          survive ? center_cell : 4'd0;

    // Majority of 3 species (1..7): two same -> that one; else tiebreak to first
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
            init_phase <= 0;
            init_addr  <= 0;
            lfsr       <= 16'hACE1;
            center_cell   <= 0;
            alive_count   <= 0;
            species_a     <= 0;
            species_b     <= 0;
            species_c     <= 0;
            species_count <= 0;
            neighbor_idx  <= 0;
        end else begin
            case (state)
                S_INIT: begin
                    addr <= init_addr;
                    din  <= (lfsr[1:0] == 2'b00) ? {1'b0, lfsr[4:2]} + 4'd1 : 4'd0;  // ~25% alive, species 1..7
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
                        ram_select <= ~ram_select;
                        cell_index <= 0;
                        x          <= 0;
                        y          <= 0;
                        state      <= S_READ_CENTER;
                    end
                end

                S_READ_CENTER: begin
                    we0 <= 0;
                    we1 <= 0;
                    addr <= {y, x};
                    center_cell <= dout_src;   // use previous cycle's read (pipeline: next state will use this)
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
                    // This cycle: output neighbor address; dout_src is from *previous* neighbor
                    if (neighbor_idx > 3'd0) begin
                        if (dout_src != 4'd0) begin
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
                    if (dout_src != 4'd0) begin
                        alive_count <= alive_count + 4'd1;
                        if (species_count == 2'd0) species_a <= dout_src;
                        else if (species_count == 2'd1) species_b <= dout_src;
                        else if (species_count == 2'd2) species_c <= dout_src;
                        if (species_count < 2'd3) species_count <= species_count + 2'd1;
                    end
                    state <= S_ADVANCE;
                end

                S_ADVANCE: begin
                    // Write new state to update bank only (we0/we1 from ram_select)
                    addr <= {y, x};
                    din  <= new_cell;
                    if (new_cell != center_cell) begin  // skip write if unchanged
                        we0  <= ram_select;
                        we1  <= ~ram_select;
                    end else begin
                        we0 <= 0;
                        we1 <= 0;
                    end
                    if (cell_index == 16'd65535) begin
                        state <= S_IDLE;
                        we0   <= 0;
                        we1   <= 0;
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
