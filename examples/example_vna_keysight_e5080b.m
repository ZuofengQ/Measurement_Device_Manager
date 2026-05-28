function saved = example_vna_keysight_e5080b()
outputFolder = setup_example_environment();
labdevices.core.resetVisaConnections('TCPIP0::192.168.1.27::inst0::INSTR');

vna = labdevices.vna.KeysightE5080B();
vna.connect();
cleanupObj = onCleanup(@() vna.disconnect()); %#ok<NASGU>

data = vna.acquire(1, 'Fresh', false);

saved = vna.saveData(data, 'Folder', outputFolder, 'Formats', {'mat', 'csv', 'png'});
% 手动命名时改用：
% saved = vna.saveData(data, 'Folder', outputFolder, ...
%     'BaseName', 'vna_current_chan1', 'Formats', {'mat', 'csv', 'png'});

disp(saved);
end
