function saved = example_scope_rigol_instant()
outputFolder = setup_example_environment();
labdevices.core.resetVisaConnections('TCPIP::192.168.1.49::INSTR');

acquisitionChannels = [3 4];
channelDisplay = struct('ch3', 1, 'ch4', 1);
channelScaleVdiv = struct('ch3', 0.2, 'ch4', 0.2);
channelOffsetV = struct('ch3', 0.0, 'ch4', 0.0);
triggerSource = 'CHAN3';

scope = labdevices.scope.RigolDHO4204();
scope.connect();
cleanupObj = onCleanup(@() scope.disconnect()); 

scope.configure( ...
    'TimebaseScaleSdiv', 1e-3, ...
    'ChannelDisplay', channelDisplay, ...
    'ChannelScaleVdiv', channelScaleVdiv, ...
    'ChannelOffsetV', channelOffsetV, ...
    'TriggerSource', triggerSource, ...
    'TriggerSlope', 'POS', ...
    'TriggerLevelV', 0.0);

data = scope.acquire(acquisitionChannels, 'Mode', 'NORM');

saved = scope.saveData(data, 'Folder', outputFolder, 'Formats', {'mat', 'csv', 'png'});
% 手动命名时改用：
% saved = scope.saveData(data, 'Folder', outputFolder, ...
%     'BaseName', 'rigol_instant_ch1_ch2', 'Formats', {'mat', 'csv', 'png'});

disp(saved);
end
