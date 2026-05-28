function saved = example_osa_ceyear_6362d()
outputFolder = setup_example_environment();
osaAlias = "black";

osa = labdevices.osa.CeyearOSA6362D(osaAlias);
osa.connect();
cleanupObj = onCleanup(@() osa.disconnect()); %#ok<NASGU>

osa.configure( ...
    'CenterWavelengthNm', 1550, ...
    'SpanNm', 20, ...
    'ResolutionNm', 0.05, ...
    'SweepMode', 'SING');

data = osa.acquire({'TRD'}, 'Fresh', true);

saved = osa.saveData(data, 'Folder', outputFolder, 'Formats', {'mat', 'csv', 'png'});
% 手动命名时改用：
% saved = osa.saveData(data, 'Folder', outputFolder, ...
%     'BaseName', 'osa_black_cband', 'Formats', {'mat', 'csv', 'png'});

disp(saved);
end
