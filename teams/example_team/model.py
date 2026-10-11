def decide(observation):
    self_state = observation["self"]
    enemies = observation["visible_enemies"]

    throttle = 1.0 if self_state["speed"] < 8.0 else 0.0
    turn = 0.3 if enemies else 0.0
    jump = False
    return throttle, turn, jump
