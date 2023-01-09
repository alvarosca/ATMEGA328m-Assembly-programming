%%
% THIS IS THE MATLAB CODE USED TO READ THE SAMPLES
% SENT BY TO THE MICROCONTROLLER TO THE COMPUTER
% SO THAT WE CAN OBTAIN A GRAPH OF THE RESULTS

clear all;
clc

t=1:10000;
begin=9250;
T=128*13/(16*10^3);
puerto='COM6';

delete(instrfind({'Port'},{puerto}));
puerto_serial=serial(puerto);
puerto_serial.InputBufferSize=10001;
puerto_serial.BaudRate=115200;
puerto_serial.timeout=30;
warning('off','MATLAB:serial:fscanf:unsuccesfulRead');

fopen(puerto_serial);

y=fread(puerto_serial, length(t), 'uint8');

%%
% Generate the graph of the RC circuit voltage
% Generar el gráfico de la tensión del RC

xcyan = (1/255)*[0,255,255];%Color de línea%
dblue = (1/255)*[0,0,35];%Color de fondo%
plot([(begin:10000)-begin]*T,y(begin:10000)*5/255,'color', xcyan , 'linewidth', 3)
ylim([-0.1,5.1])

grid on
grid minor
box on
%legend([""]);
xlabel('$\textbf{t[ms]}$', 'interpreter', 'latex')
ylabel('$\textbf{Vc[V]}$', 'interpreter', 'latex')
ax = gca;
set(gca, 'color', dblue);
set(gcf, 'color', dblue);
ax.Title.Color = 'white';
ax.XLabel.Color = 'white';
ax.YLabel.Color = 'white';
ax.XColor = 'white';
ax.YColor = 'white';
ax.GridAlpha = 0.5;
ax.GridColor = 'white';
ax.MinorGridColor = 'white';
ax.MinorGridAlpha = 0.5;

hold off

%%
% Extract the initial message
% Extraer el mensaje inicial
z=char(y);
x=transpose(z(1:100));
g=extractBetween(x,"** ", " **");
disp(g);

%%
% Close the model and delete the variables
% Cerrar el puerto y borrar las variables
fclose(puerto_serial);
delete(puerto_serial);
clear all;




