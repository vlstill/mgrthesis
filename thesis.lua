memSuffixes = { "B", "kB", "MB", "GB" }
siSuffixes = { "", "k", "M", "G" }

function round( x )
    return math.floor( x + 0.5 )
end

function fix( x )
    if x % 1 == 0 then
        return math.floor( x )
    else
        return x
    end
end

function log10( n )
    return math.log( n ) / math.log( 10 )
end

function nround( x, n )
    if x > 10 ^ n then
        return round( x )
    else
        local adj = 10 ^ (n - math.floor( log10( x ) ) - 1)
        if x < 1 then
            adj = adj / 10
        end
        return fix( round( x * adj ) / adj )
    end
end

function unit( n, i, mul, suff )
    if n > 1000 then
        return unit( n / mul, i + 1, mul, suff )
    else
        local u = suff[ i ];
        return nround( n, 3 ) .. "\\," .. u
    end
end

function mem( n )
    return unit( n, 1, 1024, memSuffixes )
end

function si( n )
    return unit( n, 1, 1000, siSuffixes )
end

function speedup( x, y )
    return "$" .. nround( x / y, 3 ) .. "\\times$"
end

function wmoptline( name, array )
    local str = "\\texttt{" .. name .. "}"
    local base = array[1]
    for i, v in ipairs( array ) do
        str = str .. " & " .. si( v )
        if i ~= 1 then
            str = str .. " & " .. speedup( base, v )
        end
    end
    return str
end
