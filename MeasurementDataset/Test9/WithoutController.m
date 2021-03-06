Phi = @(q)[q(1) -q(2) -q(3) -q(4);     % for q o p = Phi(q) * p
          q(2) q(1)  -q(4) q(3);
          q(3) q(4)  q(1)  -q(2);
          q(4) -q(3) q(2)  q(1)];           
Gamma = @(p)[p(1) -p(2) -p(3) -p(4);   % for q o p = Gamma(p) * q
             p(2) p(1) p(4) -p(3);
             p(3) -p(4) p(1) p(2);
             p(4) p(3) -p(2) p(1)];  

devec = [0,1,0,0;0,0,1,0;0,0,0,1]; % 'v' in notes
vec = [0,0,0;1,0,0;0,1,0;0,0,1]; % '^' in notes
I_conj = diag([1,-1,-1,-1]);

addpath('C:\Users\Thomas\Documents\Kugle-MATLAB\DataProcessing\functions');
addpath('C:\Users\Thomas\Documents\Kugle-MATLAB\Model\generated');
addpath('C:\Users\Thomas\Documents\Kugle-MATLAB\Parameters');
Constants_Kugle;
Parameters_General;

DumpFolder = [pwd '/../Test1_Fast/'];
data = LoadDump(DumpFolder, '');
vicon = LoadVicon(DumpFolder, '');
[data, vicon] = DumpViconTimeSynchronization(data, vicon);
[data, vicon] = TrimSynced(data, vicon, 25, 36.5); % 57.5
%[data, vicon] = TrimSynced(data, vicon, 25+8, 5); % 57.5

% Aligns MTI and Vicon yaw with estimated yaw
EstMTIyawOffset = data.yaw(1) - data.mti_yaw(1);
[data.mti_q, data.mti_dq, data.mti_omega_inertial] = QuaternionYawOffset(data.mti_q, data.mti_dq, EstMTIyawOffset, true);
mti_eul = quat2eul(data.mti_q);
data.mti_roll = mti_eul(:,3);
data.mti_pitch = mti_eul(:,2);
data.mti_yaw = unwrap(mti_eul(:,1));

EstViconyawOffset = data.yaw(1) - vicon.yaw(1);
[vicon.q, vicon.dq, vicon.omega_inertial] = QuaternionYawOffset(vicon.q, vicon.dq, EstViconyawOffset, true);
vicon_eul = quat2eul(vicon.q);
vicon.roll = vicon_eul(:,3);
vicon.pitch = vicon_eul(:,2);
vicon.yaw = unwrap(vicon_eul(:,1));
vicon.position = (rotz(EstViconyawOffset)*vicon.position')';
vicon.velocity = (rotz(EstViconyawOffset)*vicon.velocity')';

%% Processing
dt = data.time(2) - data.time(1);
dtheta = [0,0,0];
velocity_kinematics = [0,0];

% Compute motor angular velocities by numerical differentiation
for (i = 2:length(data.time))
    dtheta = [dtheta; (data.encoder_angle(i,:) - data.encoder_angle(i-1,:)) / dt];    
end

q_upright = eul2quat([data.yaw,zeros(length(data.time),2)],'ZYX');
dq_zero = zeros(length(data.time),4);

% Compute kinematics-based velocity 
velocity_kinematics_est = ForwardKinematics(dtheta(:,1)',dtheta(:,2)',dtheta(:,3)',data.dq(:,1)',data.dq(:,2)',data.dq(:,3)',data.dq(:,4)',data.q(:,1)',data.q(:,2)',data.q(:,3)',data.q(:,4)',rk,rw)';
velocity_kinematics_mti = ForwardKinematics(dtheta(:,1)',dtheta(:,2)',dtheta(:,3)',data.mti_dq(:,1)',data.mti_dq(:,2)',data.mti_dq(:,3)',data.mti_dq(:,4)',data.mti_q(:,1)',data.mti_q(:,2)',data.mti_q(:,3)',data.mti_q(:,4)',rk,rw)';
velocity_kinematics_upright = ForwardKinematics(dtheta(:,1)',dtheta(:,2)',dtheta(:,3)',dq_zero(:,1)',dq_zero(:,2)',dq_zero(:,3)',dq_zero(:,4)',q_upright(:,1)',q_upright(:,2)',q_upright(:,3)',q_upright(:,4)',rk,rw)';
%velocity_kinematics = ForwardKinematics(dtheta(:,1)',dtheta(:,2)',dtheta(:,3)',0*data.dq(:,1)',0*data.dq(:,2)',0*data.dq(:,3)',0*data.dq(:,4)',data.q(:,1)',data.q(:,2)',data.q(:,3)',data.q(:,4)',rk,rw)';

%% Motor angular velocity
fig = figure(1); set(fig, 'NumberTitle', 'off', 'Name', 'Motor angular velocity');
plot(data.time, dtheta(:,1), data.time, dtheta(:,2), data.time, dtheta(:,3)); ylabel('rad/s'); title('Motor angular velocities'); legend('Motor 0', 'Motor 1', 'Motor 2');
xlabel('Time [s]');

%% Orientation
fig = figure(2); set(fig, 'NumberTitle', 'off', 'Name', 'Orientation');
subplot(3,1,1); plot(vicon.time, rad2deg(vicon.roll)); ylabel('Angle [deg]'); title('Roll');
subplot(3,1,2); plot(vicon.time, rad2deg(vicon.pitch)); ylabel('Angle [deg]'); title('Pitch');
subplot(3,1,3); plot(vicon.time, rad2deg(vicon.yaw), data.time, rad2deg(unwrap(data.yaw)), data.time, rad2deg(unwrap(data.mti_yaw))); ylabel('Angle [deg]'); title('Yaw');
xlabel('Time [s]');

%% VEKF comparison
fig = figure(4); set(fig, 'NumberTitle', 'off', 'Name', 'Velocity comparison');
ax1 = subplot(2,1,1); plot(data.time, velocity_kinematics_est(:,1), vicon.time, vicon.velocity(:,1), data.time, data.velocity(:,1)); ylabel('m/s'); title('dx'); legend('Kinematics', 'Vicon', 'VEKF');
ax2 = subplot(2,1,2); plot(data.time, velocity_kinematics_est(:,2), vicon.time, vicon.velocity(:,2), data.time, data.velocity(:,2)); ylabel('m/s'); title('dy'); legend('Kinematics', 'Vicon', 'VEKF');
linkaxes([ax1,ax2],'x');
xlabel('Time [s]');

%% Velocity estimation error
vicon_velocity = interp1(vicon.time, vicon.velocity, data.time, 'linear', 'extrap');
velocity_error = data.velocity - vicon_velocity(:,1:2);

fig = figure(5); set(fig, 'NumberTitle', 'off', 'Name', 'Velocity estimation error');
ax1 = subplot(2,1,1); plot(data.time, velocity_error(:,1)); ylabel('m/s'); title('dx error');
ax2 = subplot(2,1,2); plot(data.time, velocity_error(:,2)); ylabel('m/s'); title('dy error');
linkaxes([ax1,ax2],'x');
xlabel('Time [s]');

%% Store data
out = [vicon.time, vicon.velocity(:,1), vicon.velocity(:,2)];
out = Downsample(out, 2); % downsample plot data
headers = {'time', 'velocity_x', 'velocity_y'};
csvwrite_with_headers('without_controller_vicon.csv', out, headers);

out = [data.time, dtheta(:,1), dtheta(:,2), dtheta(:,3), velocity_kinematics_est, data.velocity, velocity_error];
out = Downsample(out, 2); % downsample plot data
headers = {'time', 'dtheta0', 'dtheta1', 'dtheta2', 'kinematics_velocity_x', 'kinematics_velocity_y', 'vekf_velocity_x', 'vekf_velocity_y', 'velocity_error_x', 'velocity_error_y'};
csvwrite_with_headers('without_controller_system.csv', out, headers);