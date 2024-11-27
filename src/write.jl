function write_file(io::IO, sfrm::SfrmFile)
    for field in HEADER_OREDER
        key = @sprintf("%-*s:", KEY_LEN - 1, field)
        value = ""
        
    end
end