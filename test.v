
module test;

    reg a;
    reg b;
    wire c;

    assign c = a & b;

    initial begin
        $dumpfile("test.vcd");
        $dumpvars(0, test);

        a = 0;
        b = 0;
        #10;

        a = 0;
        b = 1;
        #10;

        a = 1;
        b = 0;
        #10;

        a = 1;
        b = 1;
        #10;

        $finish;
    end

endmodule