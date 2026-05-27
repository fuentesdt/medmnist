function h = hashConfig(cfg)
%HASHCONFIG Return an 8-character hex SHA-256 prefix of the JSON-encoded config.

    json = jsonencode(cfg);
    try
        md = java.security.MessageDigest.getInstance('SHA-256');
        md.reset();
        jBytes = md.digest(unicode2native(json, 'UTF-8'));
        b = typecast(int8(jBytes), 'uint8');
        h = lower(reshape(dec2hex(b, 2)', 1, []));
        h = h(1:8);
    catch
        % Java SHA-256 unavailable; fall back to a weak numeric hash.
        h = sprintf('%08x', mod(sum(double(json)), 2^32));
    end
end
