function bounds = getLimits(obj)
    % Return the boundary values (limits) of the joint position/velocity
    % variables, and torques.
    %
    % Return values:
    % bounds: the boundaries @type struct
    
    limits = [obj.Joints.Limit];
    
    bounds = struct;
    
    q_lb = [limits.lower]';
    q_ub = [limits.upper]';
    
    bounds.states.x.lb = q_lb;
    bounds.states.x.ub = q_ub;
    
    dq_ub = [limits.velocity]';
    dq_lb = -dq_ub;
    
    bounds.states.dx.lb = dq_lb;
    bounds.states.dx.ub = dq_ub;
    
    bounds.states.ddx.lb = -10000*ones(obj.numState,1);
    bounds.states.ddx.ub = 10000*ones(obj.numState,1);
    
    control = fieldnames(obj.Gmap.Control);
    gf = obj.Gmap.Control.(control{1});
    
    u_ub = double(gf'*[limits.effort]');
    u_lb = -u_ub;
    
    bounds.inputs.u.lb = u_lb;
    bounds.inputs.u.ub = u_ub;
end