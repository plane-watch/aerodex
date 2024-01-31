class AircraftProcessor
  MANUFACTURER_REPLACEMENT_PATTERNS = [
    [/The Boeing Company/i, "Boeing"],
    [/Airbus Industrie/i, "Airbus"],
    [/Cessna Aircraft Company/i, "Cessna"],
    [/Piper Aircraft.*$/i, "Piper"],
    [/The New Piper.*$/i, "Piper"],
    [/Beech.*$/i, "Beechcraft"],
    [/Pilatus Aircraft Ltd/i, "Pilatus"],
    [/Fokker.*$/i, "Fokker"],
    [/Atr - Gie Avions.*$/i, "ATR"],
    [/Fairchild.*$/i, "Fairchild"],
    [/S.A.A.B..*$/i, "SAAB"],
    [/North American Aviation Inc/i, "North American Aviation"],
    [/Robinson Helicopter Co/i, "Robinson"],
    [/Embraer.*$/i, "Embraer"],
    [/Costruzioni Aeronautiche Tecnam.*$/i, "Tecnam"],
    [/Tecnam.*$/i, "Tecnam"],
    [/Commonwealth Aircraft Corporation.*$/i, "CAC"],
    [/British Aerospace.*$/i, "British Aerospace"],
    [/Partenavia Costruzioni Aeronautiche.*$/i, "Partenavia"],
    [/Diamond Aircraft.*$/i, "Diamond"],
    [/de Havilland.*$/i, "de Havilland"],
    [/GippsAero Pty Ltd/i, "GippsAero"],
    [/Gippsland Aeronautics Pty Ltd/i, "GippsAero"],
    [/S.O.C.A.T.A.*$/i, "SOCATA"],
    [/Dassault.*$/i, "Dassault"],
    [/Mooney Aircraft Corp/i, "Mooney"],
    [/Textron Aviation.*$/i, "Textron Aviation"],
    [/American Champion.*$/i, "American Champion"],
    [/Cirrus Design Corporation.*$/i, "Cirrus"],
    [/Airbus Helicopters.*$/i, "Airbus Helicopters"],
    [/Aerospatiale.*$/i, "Aerospatiale"],
    [/Eurocopter.*$/i, "Eurocopter"],
    [/Bell Helicopter Textron.*$/i, "Bell Textron"],
    [/Bell Textron.*$/i, "Bell Textron"],
    [/Costruzioni Aeronautiche Giovanni Agusta/i, "Agusta"],
    [/Agusta S.*$/i, "Agusta"],
    [/Agusta Aerospace.*$/i, "Agusta"],
    [/Agusta, S.*$/i, "Agusta"],
    [/Agustawestland.*$/i, "AgustaWestland"],
    [/Leonardo S.P.A.*$/i, "Leonardo"],
    [/Finmeccanica S.P.A.*$/i, "Leonardo"],
    [/Sikorsky Aircraft.*$/i, "Sikorsky"],
    [/Beech Aircraft Corp/i, "Beech"],
    [/Fairchild I.*$/i, "Fairchild"],
    [/Fokker Aircraft B.V./i, "Fokker"],
    [/Atr - Gie Avions.*/i, ""],
    [/Pilatus Aircraft Ltd./i, "Pilatus"]
  ]

  AIRCRAFT_MODEL_PATTERNS = [
    [/^A(3[0-9]{3})-(\d{1,2})\d{2}/, 'A\1-\200'],
    [/F28 MK 0100/, '100'],
    [/F28MK0100/, '100'],
    [/F28 MK 070/, '70'],
    [/F28 MK 0070/, '70'],
    [/F28 MK070/, '70'],
    [/F28 MK0070/, '70'],
    [/F28MK070/, '70'],
    [/F28MK0070/, '70'],
    [/F27 MK 50/, '50'],
    [/MK/, 'Mk'],
    [/EMB-110P1/, 'EMB-110 P1'],
    [/EMB-135BJ/, 'ERJ-135 BJ Legacy'],
    [/EMB-135KL/, 'ERJ-135 KL'],
    [/EMB-145LR/, 'ERJ-145 LR'],
    [/ERJ 190-100lr/, 'ERJ 190-100 LR'],
    [/EMB-500/, 'EMB-500 Phenom 100'],
    [/EMB-505/, 'EMB-500 Phenom 300'],
    [/AW /, 'AW'],
    [/AEROPRAKT/, 'A'],
    [/BETA/, 'Beta'],
    [/DA /, 'DA'],
    [/DA-/, 'DA'],
  ]

  AIRCRAFT_MODEL_TO_FAMILY = [
    [/BD-500-1A10/, 'A220-200'],
    [/BD-500-1A11/, 'A220-300'],
    [/^A([234][0-9]{2})-(\d{1,2})\d{2}/, 'A\1-\200'],
    [/^B(7[0-9]{2})-(\d{1,2})\d{2}/, 'B\1-\200'],
    [/PC-(\d+).*/, 'PC-\1'],
    [/(.*)\/,/, '\1'],
  ]

  ICAO_MODEL_PATTERN = [
    [/^A-([234]\d{2,3})-/, 'A\1-'],         # Airbus A-3XX-XXX -> A3XX-XXX
    [/^A-([234]\d{2,3})(.*)?$/, 'A\1\2'],   # Airbus A-3XX -> A3XX
    [/^A-([234]00\w*)(-?)/, 'A\1\2'],       # Airbus A-300XX-XXX -> A300XX-XXX or A-300XX -> A300XX
    [/^C-212/, 'C212'],                     # Airbus/CASA C-212 -> C212
    [/^ACJ \(A-319\)/, 'ACJ-319'],          # Airbus ACJ (A3-319) -> ACJ-319
  ]

end