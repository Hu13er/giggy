pub const SpawnPoint = struct {
    id: u8 = 0,
};

pub const SpawnPointView = struct {
    pub const Of = SpawnPoint;
    id: *u8,
};

pub const RoomTransition = struct {
    alpha: f32,
};

pub const RoomTransitionView = struct {
    pub const Of = RoomTransition;
    alpha: *f32,
};

pub const Room = struct {
    id: u32,
};

pub const RoomView = struct {
    pub const Of = Room;
    id: *u32,
};

pub const Teleport = struct {
    room_id: u32,
    // Which SpawnPoint.id to use in the destination room. 0 means "any/default".
    spawn_id: u8 = 0,
};

pub const TeleportView = struct {
    pub const Of = Teleport;
    room_id: *u32,
    spawn_id: *u8,
};

pub const TestComponent = struct {
    x: u32,
};

pub const TestComponentView = struct {
    pub const Of = TestComponent;
    x: *u32,
};
