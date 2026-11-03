// Sound-lab controls live in the 50 MHz application domain. The four board
// switches are synchronized here and the complete control word remains stable
// around control_toggle for the audio-domain mailbox receiver.
module sound_lab_control (
    input  wire       clk,
    input  wire       rst,
    input  wire       lab_active_request,
    input  wire [3:0] switch_async,
    input  wire       amplitude_cycle_pulse,
    input  wire       mute_toggle_pulse,
    input  wire       quiz_active,
    input  wire [1:0] quiz_frequency,
    input  wire [1:0] quiz_amplitude,
    input  wire [1:0] quiz_waveform,
    input  wire       quiz_muted,
    input  wire       quiz_song_enable,

    output reg        lab_active,
    output reg  [1:0] frequency_select,
    output reg  [1:0] amplitude_level,
    output reg  [1:0] waveform_select,
    output reg        muted,
    output reg        song_enable,
    output reg        control_toggle
);

reg [3:0] switch_sync1;
reg [3:0] switch_sync2;
reg [1:0] free_amplitude;
reg       free_muted;

wire [1:0] requested_frequency =
    ({switch_sync2[1], switch_sync2[0]} == 2'b00) ? 2'd0 :
    ({switch_sync2[1], switch_sync2[0]} == 2'b01) ? 2'd1 : 2'd2;

wire [1:0] requested_waveform =
    ({switch_sync2[3], switch_sync2[2]} == 2'b00) ? 2'd0 :
    ({switch_sync2[3], switch_sync2[2]} == 2'b01) ? 2'd1 : 2'd2;

wire [1:0] desired_frequency = quiz_active ? quiz_frequency : requested_frequency;
wire [1:0] desired_amplitude = quiz_active ? quiz_amplitude : free_amplitude;
wire [1:0] desired_waveform  = quiz_active ? quiz_waveform : requested_waveform;
wire       desired_muted     = quiz_active ? quiz_muted : free_muted;
// Dynamic listening questions use a fixed single tone, while the ordinary
// page-08 exercise identifies the Xiao Luo Hao melody.  Keep this choice in
// the same atomic mailbox word as the other sound controls.
wire       desired_song      = !quiz_active || quiz_song_enable;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        switch_sync1 <= 4'd0;
        switch_sync2 <= 4'd0;
    end else begin
        switch_sync1 <= switch_async;
        switch_sync2 <= switch_sync1;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        free_amplitude <= 2'd1;
        free_muted     <= 1'b0;
    end else if (!lab_active_request) begin
        free_amplitude <= 2'd1;
        free_muted     <= 1'b0;
    end else if (!quiz_active) begin
        if (amplitude_cycle_pulse) begin
            if (free_amplitude == 2'd2)
                free_amplitude <= 2'd0;
            else
                free_amplitude <= free_amplitude + 2'd1;
        end else if (mute_toggle_pulse) begin
            free_muted <= ~free_muted;
        end
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        lab_active       <= 1'b0;
        frequency_select <= 2'd0;
        amplitude_level  <= 2'd1;
        waveform_select  <= 2'd0;
        muted             <= 1'b0;
        song_enable       <= 1'b0;
        control_toggle    <= 1'b0;
    end else begin
        if (!lab_active_request) begin
            // Preload stable switch choices while inactive without publishing.
            if (lab_active)
                control_toggle <= ~control_toggle;
            lab_active      <= 1'b0;
            frequency_select <= requested_frequency;
            waveform_select  <= requested_waveform;
            amplitude_level  <= 2'd1;
            muted            <= 1'b0;
            song_enable      <= 1'b0;
        end else if (!lab_active ||
                     (frequency_select != desired_frequency) ||
                     (amplitude_level != desired_amplitude) ||
                     (waveform_select != desired_waveform) ||
                     (muted != desired_muted) ||
                     (song_enable != desired_song)) begin
            // Publish one complete word for free-lab changes, quiz overrides,
            // and source transitions.  The audio domain never sees a partial
            // frequency/amplitude/waveform update.
            lab_active       <= 1'b1;
            frequency_select <= desired_frequency;
            amplitude_level  <= desired_amplitude;
            waveform_select  <= desired_waveform;
            muted             <= desired_muted;
            song_enable       <= desired_song;
            control_toggle    <= ~control_toggle;
        end
    end
end

endmodule
