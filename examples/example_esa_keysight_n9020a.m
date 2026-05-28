function saved = example_esa_keysight_n9020a()
outputFolder = setup_example_environment();
labdevices.core.resetVisaConnections('TCPIP0::192.168.1.45::inst0::INSTR');

esa = labdevices.esa.KeysightN9020A();
esa.connect();
cleanupObj = onCleanup(@() esa.disconnect()); %#ok<NASGU>

data = esa.acquire(1, 'Fresh', false);

saved = esa.saveData(data, 'Folder', outputFolder, 'Formats', {'mat', 'csv', 'png'});
% 手动命名时改用：
% saved = esa.saveData(data, 'Folder', outputFolder, ...
%     'BaseName', 'esa_current_trace1', 'Formats', {'mat', 'csv', 'png'});

disp(saved);
end
