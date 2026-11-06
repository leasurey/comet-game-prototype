## EventBus — 全局只读信号总线
##
## 职责边界：
##   只转发信号，不含任何逻辑，不持有任何模块引用。
##
## 存在的理由：
##   L1/L2 各模块彼此不认识，也不认识表现层。表现层需要一个统一入口订阅状态变化，
##   否则每个 UI 都要去找每个 Manager 连线，依赖关系会迅速退化成网状。
##
## 使用约束：
##   1. 只有状态的拥有者模块可以 emit（由 GameServices 转接）。
##   2. 订阅者的回调内**不得**反向修改 L1/L2 状态，避免回调期重入。
##
## 继承 RefCounted：由 GameServices 持有，不进场景树。

class_name EventBus
extends RefCounted

signal world_changed(from_world_id: String, to_world_id: String, reason_id: String)
signal event_triggered(event_id: String, from_world_id: String, to_world_id: String, log_text: String)
signal location_entered(location_id: String, display_name: String)
signal location_failed(location_id: String, error: String)
signal tick_advanced(tick: int)
