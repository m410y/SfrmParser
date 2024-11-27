module SfrmParser

using FileIO
using Dates
using Printf

struct SfrmFile
    header::Dict{String,Any}
    image::Matrix{Int32}
end

include("consts.jl")
include("parse.jl")
include("write.jl")

function load(f::File{format"SFRM"})
    s = open(f).io
    header = read_header(io)
    format = SfrmImageFormat(header)
    image = read_image(io, format)
    SfrmFile(header, image)
end

end
