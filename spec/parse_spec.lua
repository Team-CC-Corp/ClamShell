describe("parser tests", function()
    dofile(shell.resolve("lib/parse.lua"))

    describe("command", function()
        it("string", function()
            local parsed = parse [['foobar']]
            assert.same(
                { { tag = "command",
                    { tag = "string", "foobar" }
                } },
                parsed
            )
        end)

        it("variable", function()
            local parsed = parse [[$foobar]]
            assert.same(
                { { tag = "command",
                    { tag = "variable", "foobar" }
                } },
                parsed
            )
        end)

        it("subcommand", function()
            local parsed = parse [[$(foobar)]]
            assert.same(
                { { tag = "command",
                    { tag = "command", { tag = "string", "foobar" } }
                } },
                parsed
            )
        end)

        it("compound", function()
            local parsed = parse [["foo bar $baz"]]
            assert.same(
                { { tag = "command",
                    { tag = "compound",
                        { tag = "string", "foo bar "},
                        { tag = "variable", "baz"}
                    }
                } },
                parsed
            )
        end)

        it("double quote string", function()
            local parsed = parse [["foo bar"]]
            assert.same(
                { { tag = "command",
                    { tag = "string", "foo bar" }
                } },
                parsed
            )
        end)


        it("arguments", function()
            local parsed = parse [[foobar baz 'another']]
            assert.same(
                { { tag = "command",
                    { tag = "string", "foobar" },
                    { tag = "string", "baz" },
                    { tag = "string", "another" },
                } },
                parsed
            )
        end)

        it("equals arguments", function()
            -- This used to break under the old parser
            local parsed = parse [[foobar --baz=another]]
            assert.same(
                { { tag = "command",
                    { tag = "string", "foobar" },
                    { tag = "string", "--baz=another" },
                } },
                parsed
            )
        end)
    end)

    it("set", function()
        local parsed = parse [[foo=bar]]
        assert.same(
            { { tag = "set",
                { tag = "string", "foo" },
                { tag = "string", "bar" },
            } },
            parsed
        )
    end)

    it("pipe", function()
        local parsed = parse [[foo | bar > baz]]
        assert.same(
            { { tag = "pipe",
                { tag = "command", { tag = "string", "foo" } },
                { tag = "write",
                    { tag = "command", { tag = "string", "bar" } },
                    { tag = "string", "baz" }
                },
            } },
            parsed
        )
    end)

    it("pipe compound", function()
        -- TODO: Check it actually works
        local parsed = parse [[foo | $(bar | baz)]]
    end)

    it("pipe nested", function()
        -- TODO: Check it actually works
        local parsed = parse [[(foo || bar) && baz]]
    end)

    it("pipe nested ii", function()
        -- TODO: Check it actually works
        local parsed = parse [[foo || (bar && baz)]]
    end)

    describe("block", function()
        it("if", function()
            local parsed = parse [[if echo { cat "foobar" } else { echo; echo; }]]
            assert.same(
                { { tag = "if",
                    { tag = "command", { tag = "string", "echo" } },
                    {
                        { tag = "command",
                            { tag = "string", "cat" },
                            { tag = "string", "foobar" }
                        },
                    },
                    { tag = "else",
                        {
                            { tag = "command", { tag = "string", "echo" } },
                            { tag = "command", { tag = "string", "echo" } },
                        },
                    }
                } },
                parsed
            )
        end)

        it("while", function()
            local parsed = parse [[while echo { cat "foobar" }]]
            assert.same(
                { { tag = "while",
                    { tag = "command", { tag = "string", "echo" } },
                    {
                        { tag = "command",
                            { tag = "string", "cat" },
                            { tag = "string", "foobar" }
                        },
                    },
                } },
                parsed
            )
        end)

        it("for", function()
            local parsed = parse [[for var = foo { cat $var }]]
            assert.same(
                { { tag = "for",
                    { tag = "string", "var" },
                    { tag = "command", { tag = "string", "foo" } },
                    {
                        { tag = "command",
                            { tag = "string", "cat" },
                            { tag = "variable", "var" }
                        },
                    },
                } },
                parsed
            )
        end)
    end)
end)
