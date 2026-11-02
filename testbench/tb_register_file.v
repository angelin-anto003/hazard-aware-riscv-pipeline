
`timescale 1ns / 1ps

//==============================================================================
// Module      : tb_register_file
// Project     : Hazard-Aware RISC-V Pipeline with Branch Prediction
// DUT         : register_file
// Description : Self-checking verification environment for the RV32I
//               32 x 32-bit register file.
//
// Verification Features:
//   - 32 general-purpose registers (x0 - x31)
//   - Two independent combinational read ports
//   - One synchronous write port
//   - Active-high synchronous reset
//   - Reset priority over register writes
//   - Hardwired zero register (x0)
//   - Reference-model-based verification
//   - Automated PASS/FAIL reporting
//
// Timing Strategy:
//   - Clock period: 10 ns
//   - Stimulus applied at the falling clock edge
//   - Sequential checks performed 1 ns after the rising edge
//   - Combinational checks performed 1 ns after address changes
//   - Avoids race conditions between DUT and testbench
//
// Waveform:
//   simulations/register_file.vcd
//
// Note:
//   Run simulation from the project root directory.
//==============================================================================

module tb_register_file;

    //--------------------------------------------------------------------------
    // DUT Inputs
    //--------------------------------------------------------------------------

    reg         clk;
    reg         reset;

    reg  [4:0]  read_addr1;
    reg  [4:0]  read_addr2;

    reg         write_enable;
    reg  [4:0]  write_addr;
    reg  [31:0] write_data;

    //--------------------------------------------------------------------------
    // DUT Outputs
    //--------------------------------------------------------------------------

    wire [31:0] read_data1;
    wire [31:0] read_data2;

    //--------------------------------------------------------------------------
    // Verification Counters
    //--------------------------------------------------------------------------

    integer total_tests;
    integer passed_tests;
    integer failed_tests;

    //--------------------------------------------------------------------------
    // Reference Model and Test Data
    //--------------------------------------------------------------------------

    reg [31:0] model [0:31];
    reg [31:0] patterns [0:5];

    integer i;
    integer j;

    //--------------------------------------------------------------------------
    // DUT Instantiation
    //--------------------------------------------------------------------------

    register_file uut (
        .clk          (clk),
        .reset        (reset),

        .read_addr1   (read_addr1),
        .read_data1   (read_data1),

        .read_addr2   (read_addr2),
        .read_data2   (read_data2),

        .write_enable (write_enable),
        .write_addr   (write_addr),
        .write_data   (write_data)
    );

    //--------------------------------------------------------------------------
    // Clock Generation
    // 10 ns period, 50% duty cycle
    //--------------------------------------------------------------------------

    initial begin
        clk = 1'b0;
    end

    always #5 clk = ~clk;

    //--------------------------------------------------------------------------
    // Waveform Generation
    //--------------------------------------------------------------------------

    initial begin
        $dumpfile("simulations/register_file.vcd");
        $dumpvars(0, tb_register_file);
    end

    //==========================================================================
    // TASK 1: Single-Value Verification
    //
    // Compares actual and expected values using case inequality.
    // Detects mismatches including unknown (X) and high-impedance (Z) values.
    //==========================================================================

    task check;
        input [319:0] name;
        input [31:0]  actual;
        input [31:0]  expected;
        input [23:0]  tag;

        begin
            total_tests = total_tests + 1;

            if (actual !== expected) begin

                failed_tests = failed_tests + 1;

                $display(
                    "[FAIL] %0s [%0s] | Actual = %h | Expected = %h",
                    name, tag, actual, expected
                );

            end
            else begin

                passed_tests = passed_tests + 1;

                $display(
                    "[PASS] %0s [%0s] | Actual = %h | Expected = %h",
                    name, tag, actual, expected
                );

            end
        end
    endtask

    //==========================================================================
    // TASK 2: Dual-Port Read Verification
    //
    // Reads two independent register addresses simultaneously and verifies
    // both read-port outputs.
    //==========================================================================

    task check_dual;
        input [319:0] name;
        input [4:0]   addr1;
        input [31:0]  exp1;
        input [4:0]   addr2;
        input [31:0]  exp2;

        begin
            read_addr1 = addr1;
            read_addr2 = addr2;

            #1;

            check(name, read_data1, exp1, "RP1");
            check(name, read_data2, exp2, "RP2");
        end
    endtask

    //==========================================================================
    // TASK 3: Single-Register Read Verification
    //
    // Reads the same register through both read ports.
    //==========================================================================

    task check_reg;
        input [319:0] name;
        input [4:0]   addr;
        input [31:0]  expected;

        begin
            check_dual(
                name,
                addr, expected,
                addr, expected
            );
        end
    endtask

    //==========================================================================
    // TASK 4: Complete Register-File Verification
    //
    // Checks all 32 registers using the reference model.
    // Port 1 accesses registers in ascending order.
    // Port 2 accesses registers in descending order.
    // The complete operation is counted as one verification test.
    //==========================================================================

    task check_all;
        input [319:0] name;

        integer errors;
        integer k;

        reg [4:0] addr1;
        reg [4:0] addr2;

        begin
            errors = 0;

            for (k = 0; k < 32; k = k + 1) begin

                addr1 = k;
                addr2 = 5'd31 - addr1;

                read_addr1 = addr1;
                read_addr2 = addr2;

                #1;

                if (read_data1 !== model[addr1]) begin

                    errors = errors + 1;

                    $display(
                        "       Port 1 mismatch: x%0d | Actual = %h | Expected = %h",
                        addr1, read_data1, model[addr1]
                    );

                end

                if (read_data2 !== model[addr2]) begin

                    errors = errors + 1;

                    $display(
                        "       Port 2 mismatch: x%0d | Actual = %h | Expected = %h",
                        addr2, read_data2, model[addr2]
                    );

                end

            end

            total_tests = total_tests + 1;

            if (errors == 0) begin

                passed_tests = passed_tests + 1;

                $display("[PASS] %0s [ALL 32 REGISTERS]", name);

            end
            else begin

                failed_tests = failed_tests + 1;

                $display(
                    "[FAIL] %0s [ALL 32 REGISTERS] | Mismatches = %0d",
                    name, errors
                );

            end
        end
    endtask

    //==========================================================================
    // TASK 5: Register Write Operation
    //
    // Applies write stimulus at the falling edge.
    // DUT captures the write at the next rising edge.
    // Updates the reference model after the write completes.
    //==========================================================================

    task write_reg;
        input [4:0]  addr;
        input [31:0] data;

        begin
            @(negedge clk);

            write_addr   = addr;
            write_data   = data;
            write_enable = 1'b1;

            @(posedge clk);

            #1;

            write_enable = 1'b0;

            if (addr != 5'd0) begin
                model[addr] = data;
            end
        end
    endtask

    //==========================================================================
    // TASK 6: Disabled Write Verification
    //
    // Attempts a register write with write_enable LOW.
    // The reference model remains unchanged.
    //==========================================================================

    task write_disabled;
        input [4:0]  addr;
        input [31:0] data;

        begin
            @(negedge clk);

            write_addr   = addr;
            write_data   = data;
            write_enable = 1'b0;

            @(posedge clk);

            #1;
        end
    endtask

    //==========================================================================
    // TASK 7: Synchronous Reset Operation
    //
    // Applies reset for one complete rising clock edge.
    // Optional simultaneous write attempt verifies reset priority.
    // Clears the reference model after reset completes.
    //==========================================================================

    task reset_cycle;
        input        we;
        input [4:0]  wa;
        input [31:0] wd;

        begin
            @(negedge clk);

            reset        = 1'b1;
            write_enable = we;
            write_addr   = wa;
            write_data   = wd;

            @(posedge clk);

            #1;

            reset        = 1'b0;
            write_enable = 1'b0;

            for (i = 0; i < 32; i = i + 1) begin
                model[i] = 32'd0;
            end
        end
    endtask

    //==========================================================================
    // MAIN TEST SEQUENCE
    //==========================================================================

    initial begin

        //----------------------------------------------------------------------
        // Initialisation
        //----------------------------------------------------------------------

        reset        = 1'b0;

        read_addr1   = 5'd0;
        read_addr2   = 5'd0;

        write_enable = 1'b0;
        write_addr   = 5'd0;
        write_data   = 32'd0;

        total_tests  = 0;
        passed_tests = 0;
        failed_tests = 0;

        for (i = 0; i < 32; i = i + 1) begin
            model[i] = 32'd0;
        end

        //----------------------------------------------------------------------
        // Boundary Data Patterns
        //----------------------------------------------------------------------

        patterns[0] = 32'h00000000;
        patterns[1] = 32'hFFFFFFFF;
        patterns[2] = 32'hAAAAAAAA;
        patterns[3] = 32'h55555555;
        patterns[4] = 32'h80000000;
        patterns[5] = 32'h7FFFFFFF;

        #1;

        $display("==============================================================");
        $display("       REGISTER FILE SELF-CHECKING TESTBENCH");
        $display("==============================================================");

        //======================================================================
        // A. RESET VERIFICATION
        //======================================================================

        $display("\n--- A. Reset Verification ---");

        // A1: Initial reset
        reset_cycle(1'b0, 5'd0, 32'd0);

        check_all("A1: All registers zero after reset");

        // Populate registers before reset
        write_reg(5'd1,  32'h11111111);
        write_reg(5'd5,  32'h55555555);
        write_reg(5'd31, 32'h31313131);

        check_all("A2: Registers populated before reset");

        // A3: Reset priority over simultaneous write
        reset_cycle(1'b1, 5'd7, 32'hDEADBEEF);

        check_all("A3: Reset has priority over write");
        check_reg("A3: x7 remains zero", 5'd7, 32'd0);

        // A4: Reset must not take effect before rising edge
        write_reg(5'd3, 32'hCAFEBABE);

        @(negedge clk);

        reset = 1'b1;

        #2;

        check_reg(
            "A4: Reset inactive before rising edge",
            5'd3,
            32'hCAFEBABE
        );

        @(posedge clk);

        #1;

        reset = 1'b0;

        for (i = 0; i < 32; i = i + 1) begin
            model[i] = 32'd0;
        end

        check_reg("A5: Reset takes effect after rising edge", 5'd3, 32'd0);
        check_all("A5: All registers cleared by synchronous reset");

        // A6: Reset pulse that does not overlap a rising edge
        write_reg(5'd3, 32'hCAFEBABE);

        @(negedge clk);

        reset = 1'b1;

        #2;

        reset = 1'b0;

        @(posedge clk);

        #1;

        check_reg(
            "A6: Reset pulse between edges is ignored",
            5'd3,
            32'hCAFEBABE
        );

        // A7: Return to a clean state
        reset_cycle(1'b0, 5'd0, 32'd0);

        check_all("A7: Clean state after reset");

        //======================================================================
        // B. REGISTER WRITE VERIFICATION
        //======================================================================

        $display("\n--- B. Register Write Verification ---");

        write_reg(5'd1,  32'h00000001);
        write_reg(5'd5,  32'h00000005);
        write_reg(5'd10, 32'hA0A0A00A);
        write_reg(5'd15, 32'h15151515);
        write_reg(5'd20, 32'h2020DEAD);
        write_reg(5'd31, 32'hFACEFEED);

        check_reg("B1: Read back x1",  5'd1,  32'h00000001);
        check_reg("B2: Read back x5",  5'd5,  32'h00000005);
        check_reg("B3: Read back x10", 5'd10, 32'hA0A0A00A);
        check_reg("B4: Read back x15", 5'd15, 32'h15151515);
        check_reg("B5: Read back x20", 5'd20, 32'h2020DEAD);
        check_reg("B6: Read back x31", 5'd31, 32'hFACEFEED);

        check_all("B7: Reference model matches all registers");

        // B8: Write must not be visible before the rising edge
        @(negedge clk);

        write_addr   = 5'd12;
        write_data   = 32'h0BADF00D;
        write_enable = 1'b1;

        #2;

        check_reg(
            "B8: x12 unchanged before rising edge",
            5'd12,
            model[12]
        );

        @(posedge clk);

        #1;

        write_enable = 1'b0;
        model[12] = 32'h0BADF00D;

        check_reg(
            "B9: x12 updated after rising edge",
            5'd12,
            32'h0BADF00D
        );

        // B10: Write-enable pulse between clock edges
        @(negedge clk);

        write_addr   = 5'd13;
        write_data   = 32'h13131313;
        write_enable = 1'b1;

        #2;

        write_enable = 1'b0;

        @(posedge clk);

        #1;

        check_reg(
            "B10: Write-enable pulse between edges ignored",
            5'd13,
            model[13]
        );

        // B11: Write disabled
        write_disabled(5'd10, 32'hBAD0BAD0);

        check_reg(
            "B11: Disabled write leaves x10 unchanged",
            5'd10,
            32'hA0A0A00A
        );

        //======================================================================
        // C. DUAL READ-PORT VERIFICATION
        //======================================================================

        $display("\n--- C. Dual Read-Port Verification ---");

        check_dual(
            "C1: Simultaneous read x1 and x5",
            5'd1, model[1],
            5'd5, model[5]
        );

        check_dual(
            "C2: Simultaneous read x31 and x10",
            5'd31, model[31],
            5'd10, model[10]
        );

        // C3-C5: Combinational read without an intervening clock edge
        @(posedge clk);

        #1;

        check_dual(
            "C3: Combinational read x10 and x15",
            5'd10, model[10],
            5'd15, model[15]
        );

        check_dual(
            "C4: Combinational read x20 and x31",
            5'd20, model[20],
            5'd31, model[31]
        );

        check_dual(
            "C5: Combinational read x5 and x1",
            5'd5, model[5],
            5'd1, model[1]
        );

        // Same register accessed through both ports
        check_reg("C6: x20 through both read ports", 5'd20, model[20]);
        check_reg("C7: x31 through both read ports", 5'd31, model[31]);

        //======================================================================
        // D. ZERO REGISTER (x0) PROTECTION
        //======================================================================

        $display("\n--- D. x0 Protection ---");

        check_reg("D1: x0 initially reads zero", 5'd0, 32'd0);

        write_reg(5'd0, 32'hFFFFFFFF);

        check_reg("D2: x0 protected against FFFFFFFF", 5'd0, 32'd0);

        write_reg(5'd0, 32'hA5A5A5A5);

        check_reg("D3: x0 protected against A5A5A5A5", 5'd0, 32'd0);

        write_reg(5'd0, 32'h12345678);

        check_reg("D4: x0 protected against 12345678", 5'd0, 32'd0);

        write_reg(5'd0, 32'h80000000);

        check_reg("D5: x0 protected against 80000000", 5'd0, 32'd0);

        // Verify x0 independently on both read ports
        check_dual(
            "D6: x0 on port 1 and x31 on port 2",
            5'd0, 32'd0,
            5'd31, model[31]
        );

        check_dual(
            "D7: x5 on port 1 and x0 on port 2",
            5'd5, model[5],
            5'd0, 32'd0
        );

        check_all("D8: x0 writes do not disturb other registers");

        //======================================================================
        // E. WRITE PROTECTION VERIFICATION
        //======================================================================

        $display("\n--- E. Write Protection Verification ---");

        // E1-E2: Disabled write must not modify destination
        write_disabled(5'd20, 32'h0000BEEF);

        check_reg(
            "E1: Disabled write leaves x20 unchanged",
            5'd20,
            32'h2020DEAD
        );

        check_all("E2: Disabled write does not disturb registers");

        // E3-E6: Writing one register must not affect other registers
        write_reg(5'd9, 32'h99999999);

        check_reg("E3: x9 updated", 5'd9, 32'h99999999);
        check_reg("E4: x8 remains unchanged", 5'd8, model[8]);
        check_reg("E5: x10 remains unchanged", 5'd10, 32'hA0A0A00A);

        check_all("E6: Single write does not disturb other registers");

        // E7-E9: Boundary register write isolation
        write_reg(5'd31, 32'h0F0F0F0F);

        check_reg("E7: x31 updated", 5'd31, 32'h0F0F0F0F);
        check_reg("E8: x30 remains unchanged", 5'd30, model[30]);

        check_all("E9: x31 write does not disturb other registers");

        //======================================================================
        // F. REGISTER BOUNDARY AND DATA-PATTERN VERIFICATION
        //======================================================================

        $display("\n--- F. Register Boundary Verification ---");

        for (j = 0; j < 6; j = j + 1) begin

            // Test data patterns on the first writable register
            write_reg(5'd1, patterns[j]);

            check_reg(
                "F1: x1 boundary data pattern",
                5'd1,
                patterns[j]
            );

            // Test data patterns on the last register
            write_reg(5'd31, patterns[j]);

            check_reg(
                "F2: x31 boundary data pattern",
                5'd31,
                patterns[j]
            );

            // Simultaneous read of both boundary registers
            check_dual(
                "F3: Simultaneous x1 and x31 read",
                5'd1, patterns[j],
                5'd31, patterns[j]
            );

        end

        check_reg("F4: x0 remains zero", 5'd0, 32'd0);

        check_all("F5: Final reference-model comparison");

        //======================================================================
        // Z. FINAL RESET VERIFICATION
        //======================================================================

        $display("\n--- Final Reset Verification ---");

        reset_cycle(1'b0, 5'd0, 32'd0);

        check_all("Z1: All registers zero after final reset");

        //======================================================================
        // FINAL VERIFICATION SUMMARY
        //======================================================================

        #10;

        $display("\n==============================================================");
        $display("          REGISTER FILE VERIFICATION SUMMARY");
        $display("==============================================================");

        $display(" Total Tests : %0d", total_tests);
        $display(" Passed      : %0d", passed_tests);
        $display(" Failed      : %0d", failed_tests);

        $display("==============================================================");

        if (failed_tests == 0) begin

            $display(" REGISTER FILE VERIFICATION PASSED");

        end
        else begin

            $display(" REGISTER FILE VERIFICATION FAILED");

        end

        $display("==============================================================");

        $finish;

    end

endmodule
