export type Attribute =
  | "power"
  | "voltage"
  | "current"
  | "frequency"
  | "soc"
  | "temperature"
  | "energy"
  | "irradiance"
  | "flow_rate";

export type DeviceType = "inverter" | "battery" | "meter" | "solar" | "hvac";

export interface DeviceSpec {
  deviceId: string;
  type: DeviceType;
  site: string;
  attributes: Attribute[];
}

export const DEVICES: DeviceSpec[] = [
  {
    deviceId: "inverter-01",
    type: "inverter",
    site: "factory-A",
    attributes: ["power", "voltage", "current", "frequency"],
  },
  {
    deviceId: "inverter-02",
    type: "inverter",
    site: "factory-A",
    attributes: ["power", "voltage", "current", "frequency"],
  },
  {
    deviceId: "bess-01",
    type: "battery",
    site: "factory-A",
    attributes: ["soc", "power", "voltage", "temperature"],
  },
  {
    deviceId: "bess-02",
    type: "battery",
    site: "factory-B",
    attributes: ["soc", "power", "voltage", "temperature"],
  },
  {
    deviceId: "meter-main-01",
    type: "meter",
    site: "factory-A",
    attributes: ["power", "energy", "voltage", "current"],
  },
  {
    deviceId: "meter-main-02",
    type: "meter",
    site: "factory-B",
    attributes: ["power", "energy", "voltage", "current"],
  },
  {
    deviceId: "meter-sub-01",
    type: "meter",
    site: "factory-A",
    attributes: ["power", "energy"],
  },
  {
    deviceId: "solar-01",
    type: "solar",
    site: "factory-A",
    attributes: ["power", "irradiance", "temperature"],
  },
  {
    deviceId: "solar-02",
    type: "solar",
    site: "factory-B",
    attributes: ["power", "irradiance", "temperature"],
  },
  {
    deviceId: "chiller-01",
    type: "hvac",
    site: "factory-A",
    attributes: ["power", "temperature", "flow_rate"],
  },
];

export interface AttributeRange {
  min: number;
  max: number;
}

export const NORMAL_RANGES: Record<Attribute, AttributeRange> = {
  power: { min: 0, max: 500 },
  voltage: { min: 210, max: 240 },
  current: { min: 0, max: 100 },
  frequency: { min: 59.8, max: 60.2 },
  soc: { min: 10, max: 95 },
  temperature: { min: 15, max: 55 },
  energy: { min: 0, max: 10_000 },
  irradiance: { min: 0, max: 1_200 },
  flow_rate: { min: 0, max: 50 },
};

export function generateValue(attribute: Attribute): number {
  const range = NORMAL_RANGES[attribute];
  return range.min + Math.random() * (range.max - range.min);
}
