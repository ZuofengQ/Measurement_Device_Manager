function resetVisaConnections(resourceName)
if exist('visadevfind', 'file') ~= 2 && exist('visadevfind', 'builtin') ~= 5
    return;
end

if nargin < 1 || isempty(resourceName)
    existing = visadevfind();
else
    existing = visadevfind('ResourceName', char(string(resourceName)));
end

if isempty(existing)
    return;
end

delete(existing);
end
