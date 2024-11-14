struct SfrmImageFormat
    header_size::Integer
    data_bpp::Integer
    under_bpp::Integer
    rows::Integer
    cols::Integer
    under_len::Integer
    over1_len::Integer
    over2_len::Integer
    baseline::Integer
end
SfrmImageFormat(header::Dict{String,Any}) = SfrmImageFormat(
    BLOCK_SIZE * header["HDRBLKS"],
    header["NPIXELB"][1],
    header["NPIXELB"][2],
    header["NROWS"][1],
    header["NCOLS"][1],
    header["NOVERFL"][1],
    header["NOVERFL"][2],
    header["NOVERFL"][3],
    header["NEXP"][3]
)

function read_header_blocks!(io::IO, header::Dict{String,Any}, blocks_num::Integer)
    chunk_size = BLOCK_SIZE * blocks_num
    header_string = Vector{UInt8}(undef, chunk_size)
    read!(io, header_string)
    for line_start = 1:LINE_LEN:chunk_size
        line = String(header_string[line_start:line_start+LINE_LEN-1])
        key = rstrip(line[1:KEY_LEN-1])
        val = split(line[KEY_LEN+1:end])
        haskey(header, key) || (header[key] = Vector{SubString}())
        append!(header[key], val)
    end
    nothing
end

function bpp_signed(size::Integer)
    size == 1 ? Int8 :
    size == 2 ? Int16 :
    size == 4 ? Int32 :
    size == 8 ? Int64 :
    size == 16 ? Int128 :
    BigInt
end

function bpp_unsigned(size::Integer)
    size == 1 ? UInt8 :
    size == 2 ? UInt16 :
    size == 4 ? UInt32 :
    size == 8 ? UInt64 :
    size == 16 ? UInt128 :
    BigInt
end

function read_typed_array(io::IO, type::Type{<:Integer}, length::Integer)
    length > 0 || return nothing
    read_len = ((length * sizeof(type) + DATA_ALIGNMENT - 1) ÷ DATA_ALIGNMENT) * DATA_ALIGNMENT
    data = Vector{array_type}(undef, read_len ÷ sizeof(type))
    read!(io, data)
    data[1:length]
end

function data_merge_overflow!(
    data::AbstractArray,
    overflow::Union{AbstractArray,Nothing},
    pivot::Integer,
)
    isnothing(overflow) || data[data.==pivot] = overflow
    nothing
end

function read_header(io::IO)
    header = Dict{String,Any}()
    read_header_blocks!(io, header, BLOCKS_MIN)
    blocks_remain = parse(Int, header["HDRBLKS"][1]) - BLOCKS_MIN
    read_header_blocks!(io, header, blocks_remain)

    my_parse((type, str)) = type == String ? str : parse(type, str)
    for (key, values) in header
        if isempty(values)
            header[key] = nothing
            continue
        end
        if haskey(HEADER_FIELDS, key)
            types = HEADER_FIELDS[key]
            header[key] = Tuple(my_parse.(zip(types, values)))
            length(header[key]) == 1 && (header[key] = first(header[key]))
            continue
        end
        header[key] = join(values, " ")
    end
    if haskey(header, "CREATED")
        date = Date(header["CREATED"][1], "dd-u-yyyy")
        time = Time(header["CREATED"][2])
        header["CREATED"] = DateTime(date, time)
    end
    header
end

function read_image(io::IO, format::SfrmImageFormat)
    format.under_bpp > 0 || (format.baseline = 0)
    data = read_typed_array(io, bpp_signed(format.data_bpp), format.rows * format.cols)
    under = read_typed_array(io, bpp_unsigned(format.under_bpp), format.under_len)
    over1 = read_typed_array(io, Int16, format.over1_len)
    over2 = read_typed_array(io, Uint32, format.over2_len)
    data = Int32.(data)
    data_merge_overflow!(data, under, 0)
    data_merge_overflow!(data, over1, typemax(UInt8))
    data_merge_overflow!(data, over2, typemax(UInt16))
    data .+= format.baseline
    transpose(reshape(data, (format.cols, format.rows))[:, end:-1:begin])
end