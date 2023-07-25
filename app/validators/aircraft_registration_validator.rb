class AircraftRegistrationValidator < ActiveModel::EachValidator

  REGISTRATION_PATTERNS = [
    # USA (FAA)
    /\AN[A-Z0-9]{1,5}\z/i,

    # United Kingdom (CAA)
    /\AG-[A-Z]{4}\z/i,

    # Germany (LBA)
    /\AD-[A-Z0-9]{1,4}\z/i,

    # Australia (CASA)
    /\AVH-[A-Z]{3}\z/i,

    # Canada (Transport Canada)
    /\A(C|CF)-[A-Z0-9]{1,5}\z/i,

    # France (DGAC)
    /\AF-[A-Z0-9]{4}\z/i,

    # Brazil (ANAC)
    /\APR-[A-Z0-9]{3}\z/i,

    # Italy (ENAC)
    /\AI-[A-Z0-9]{4}\z/i,

    # Japan (JCAB)
    /\AJA[0-9]{4}[A-Z]?\z/i,

    # South Africa (SACAA)
    /\AZS-[A-Z]{3}\z/i,

    # India (DGCA)
    /\AVT-[A-Z0-9]{4}\z/i,

    # Russia (Federal Air Transport Agency)
    /\ARA-(\d{4}|[A-Z]{3})\z/i,

    # Spain (AESA)
    /\AEC-[A-Z0-9]{3}\z/i,

    # China (CAAC)
    /\AB-(\d{4}|[A-Z0-9]{3})\z/i,

    # Sweden (Transportstyrelsen)
    /\ASE-[A-Z0-9]{3}\z/i,

    # Mexico (AFAC)
    /\AX[ABC]-[A-Z0-9]{3}\z/i,

    # New Zealand (CAA)
    /\AZK-[A-Z0-9]{3}\z/i,

    # Argentina (ANAC)
    /\ALV-[A-Z0-9]{3}\z/i,

    # Netherlands (CAA-NL)
    /\APH-[A-Z0-9]{2,3}\z/i,

    # Switzerland (FOCA)
    /\AHB-[A-Z0-9]{3}\z/i,

    # Belgium (BCAA)
    /\AOO-[A-Z0-9]{3}\z/i,

    # Austria (Austro Control)
    /\AOE-[A-Z0-9]{1,4}\z/i,

    # Singapore (CAAS)
    /\A9V-[A-Z]{3}\z/i,

    # South Korea (MOLIT)
    /\AHL[0-9]{4}\z/i,

    # Indonesia (DGCA)
    /\APK-[A-Z0-9]{3}\z/i,

    # Ireland (IAA)
    /\AEI-[A-Z0-9]{3}\z/i,

    # Greece (HCAA)
    /\ASX-[A-Z0-9]{3}\z/i,

    # Turkey (DGCA)
    /\ATC-[A-Z0-9]{4}\z/i,

    # Thailand (CAAT)
    /\AHS-[A-Z0-9]{3}\z/i,

    # Philippines (CAAP)
    /\ARP-C[0-9]{4}\z/i,

    # Malaysia (CAAM)
    /\A9M-[A-Z0-9]{3}\z/i,

    # Norway (CAA)
    /\ALN-[A-Z0-9]{1,4}\z/i,

    # Finland (CAA)
    /\AOH-[A-Z0-9]{3}\z/i,

    # Portugal (ANAC)
    /\ACS-[A-Z0-9]{2,3}\z/i,

    # Denmark (CAA)
    /\AOY-[A-Z0-9]{1,3}\z/i,

    # Czech Republic (CAA)
    /\AOK-[A-Z0-9]{3,4}\z/i,

    # Poland (CAA)
    /\ASP-[A-Z0-9]{3,4}\z/i,

    # United Arab Emirates (GCAA)
    /\AA6-[A-Z0-9]{3}\z/i,

    # Saudi Arabia (GACA)
    /\AHZ-[A-Z0-9]{3}\z/i,

    # Israel (CAA)
    /\A4X-[A-Z0-9]{3}\z/i,

    # Iran (CAO)
    /\AEP-[A-Z0-9]{3}\z/i,

    # Egypt (ECAA)
    /\ASU-[A-Z0-9]{3}\z/i,

    # Kenya (KCAA)
    /\A5Y-[A-Z0-9]{3}\z/i,

    # Nigeria (NCAA)
    /\A5N-[A-Z0-9]{3}\z/i,

    # South Sudan (SSCAA)
    /\AHZJ[A-Z0-9]{3}\z/i,

    # Angola (INAVIC)
    /\AD2-[A-Z0-9]{3}\z/i,

    # Mozambique (IACM)
    /\AC9-[A-Z0-9]{3}\z/i,

    # Peru (MTC)
    /\AOB-[0-9]{4}\z/i,

    # Colombia (UAEAC)
    /\AHK-[0-9]{4}\z/i,

    # Chile (DGAC)
    /\ACC-[A-Z0-9]{3}\z/i,

    # Argentina (ANAC)
    /\ALV-[A-Z0-9]{3}\z/i,

    # Ecuador (DGAC)
    /\AHC-[A-Z0-9]{4}\z/i,

    # Venezuela (INAC)
    /\AYV[0-9]{4}\z/i,

    # Bolivia (DGAC)
    /\ACP-[0-9]{4}\z/i,

    # Paraguay (DINAC)
    /\AZP-[A-Z0-9]{3}\z/i,

    # Luxembourg (Direction de l'aviation civile)
    /\ALX-[A-Z0-9]{1,4}\z/i,

    # Croatia (Croatian Civil Aviation Agency)
    /\A9A-[A-Z0-9]{3}\z/i,

    # Hungary (Transport Authority)
    /\AHA-[A-Z0-9]{1,4}\z/i,

    # Kazakhstan (Civil Aviation Committee)
    /\AUP-[A-Z0-9]{3}\z/i,

    # Estonia (Estonian Transport Administration)
    /\AES-[A-Z0-9]{3}\z/i,

    # Latvia (Civil Aviation Agency)
    /\AYL-[A-Z0-9]{3}\z/i,

    # Lithuania (Civil Aviation Administration)
    /\ALY-[A-Z0-9]{3}\z/i,

    # Cyprus (Department of Civil Aviation)
    /\A5B-[A-Z0-9]{3}\z/i,

    # Malta (Civil Aviation Directorate)
    /\A9H-[A-Z0-9]{3}\z/i,

    # Iceland (Icelandic Transport Authority)
    /\ATF-[A-Z0-9]{3}\z/i,

    # Vietnam (Civil Aviation Authority)
    /\AVN-[A-Z0-9]{3}\z/i,

    # Pakistan (Civil Aviation Authority)
    /\AAP-[A-Z0-9]{3}\z/i,

    # Romania (Romanian Civil Aeronautical Authority)
    /\AYR-[A-Z0-9]{3}\z/i,

    # Slovakia (Transport Authority)
    /\AOM-[A-Z0-9]{3}\z/i,

    # Belarus (Civil Aviation and Air Navigation Authority)
    /\AEW-[A-Z0-9]{3}\z/i,

    # Bulgaria (Civil Aviation Administration)
    /\ALZ-[A-Z0-9]{3}\z/i,

    # Slovenia (Civil Aviation Agency)
    /\AS5-[A-Z0-9]{3}\z/i,

    # Bangladesh (Civil Aviation Authority)
    /\AS2-[A-Z0-9]{3}\z/i,

    # Myanmar (Department of Civil Aviation)
    /\AXY-[A-Z0-9]{3}\z/i,

    # Sri Lanka (Civil Aviation Authority)
    /\A4R-[A-Z0-9]{3}\z/i,

    # Guatemala (Dirección General de Aeronáutica Civil)
    /\ATG-[A-Z0-9]{3}\z/i,

    # El Salvador (Civil Aviation Authority)
    /\AYS-[A-Z0-9]{3}\z/i,

    # Costa Rica (Civil Aviation Authority)
    /\ATI-[A-Z0-9]{3}\z/i,

    # Panama (Civil Aviation Authority)
    /\AHP-[0-9]{4}\z/i,

    # Honduras (Civil Aviation Agency)
    /\AHR-[A-Z0-9]{3}\z/i,

    # Albania (Civil Aviation Authority)
    /\AZA-[A-Z0-9]{3}\z/i,

    # Malta (Civil Aviation Directorate)
    /\A9H-[A-Z0-9]{3}\z/i,

    # Tunisia (Civil Aviation and Airports Authority)
    /\ATS-[A-Z0-9]{3}\z/i,

    # Uruguay (Civil Aviation Authority)
    /\ACX-[A-Z0-9]{3}\z/i,

    # Cuba (Civil Aviation Institute)
    /\ACU-[0-9]{3}\z/i,

    # Jamaica (Civil Aviation Authority)
    /\A6Y-[A-Z0-9]{3}\z/i,

    # Bahamas (Civil Aviation Authority)
    /\AC6-[A-Z0-9]{3}\z/i,

    # Trinidad and Tobago (Civil Aviation Authority)
    /\A9Y-[A-Z0-9]{3}\z/i,

    # Barbados (Civil Aviation Department)
    /\A8P-[A-Z0-9]{3}\z/i,

    # Lebanon (Civil Aviation Authority)
    /\AOD-[A-Z0-9]{3}\z/i,

    # Jordan (Civil Aviation Regulatory Commission)
    /\AJY-[A-Z0-9]{3}\z/i,

    # Azerbaijan (Civil Aviation Administration)
    /\A4K-[A-Z0-9]{3}\z/i,

    # Georgia (Civil Aviation Agency)
    /\A4L-[A-Z0-9]{3}\z/i,

    # Uzbekistan (Civil Aviation Agency)
    /\AUK-[0-9]{4}\z/i,

    # Armenia (Civil Aviation Committee)
    /\AEK-[0-9]{3}\z/i,

    # Turkmenistan (Civil Aviation Agency)
    /\AEZ-[0-9]{3}\z/i,

    # Kyrgyzstan (Civil Aviation Agency)
    /\AEX-[0-9]{4}\z/i,

    # Nepal (Civil Aviation Authority)
    /\A9N-[A-Z0-9]{3}\z/i,

    # Laos (Department of Civil Aviation)
    /\ARDPL-[0-9]{4}\z/i,

    # Kyrgyzstan (Civil Aviation Authority)
    /\AEX-[0-9]{4}\z/i,

    # Turkmenistan (Civil Aviation Authority)
    /\AEZ-[0-9]{3}\z/i,

    # Mongolia (Civil Aviation Authority)
    /\AJU-[0-9]{4}\z/i,

    # Bhutan (Department of Air Transport)
    /\AA5-[A-Z0-9]{3}\z/i,

    # Maldives (Civil Aviation Authority)
    /\A8Q-[A-Z0-9]{3}\z/i,

    # Brunei (Department of Civil Aviation)
    /\AV8-[A-Z0-9]{3}\z/i,

    # Papua New Guinea (Civil Aviation Safety Authority)
    /\AP2-[A-Z0-9]{3}\z/i,

    # Solomon Islands (Civil Aviation Authority)
    /\AH4-[A-Z0-9]{3}\z/i,
    # Vanuatu (Civil Aviation Authority)
    /\AYJ-[A-Z0-9]{3}\z/i,

    # Samoa (Ministry of Works, Transport and Infrastructure)
    /\A5W-[A-Z0-9]{3}\z/i,

    # Tonga (Ministry of Infrastructure)
    /\AA3-[A-Z0-9]{3}\z/i,

    # Fiji (Civil Aviation Authority)
    /\ADQ-[A-Z0-9]{3}\z/i,

    # New Caledonia (Directorate of Civil Aviation)
    /\AF-O[A-Z0-9]{3}\z/i,

    # French Polynesia (Directorate of Civil Aviation)
    /\AF-[A-Z0-9]{3}\z/i,

    # Seychelles (Civil Aviation Authority)
    /\AS7-[A-Z0-9]{3}\z/i,

    # Mauritius (Department of Civil Aviation)
    /\A3B-[A-Z0-9]{3}\z/i,

    # Cambodia (State Secretariat of Civil Aviation)
    /\AXU-[A-Z0-9]{3}\z/i,

    # Samoa (Ministry of Works, Transport & Infrastructure)
    /\A5W-[A-Z0-9]{3}\z/i,

    # Cook Islands (Civil Aviation Authority)
    /\AE5-[A-Z0-9]{3}\z/i,

    # French Polynesia (Civil Aviation Authority)
    /\AF-O[A-Z0-9]{3}\z/i,

    # Tonga (Ministry of Infrastructure)
    /\AA3-[A-Z0-9]{3}\z/i,

    # Seychelles (Civil Aviation Authority)
    /\AS7-[A-Z0-9]{3}\z/i,

    # Reunion (Direction Générale de l'Aviation Civile)
    /\AF-OR[A-Z0-9]{2}\z/i,

    # New Caledonia (Direction de l'Aviation Civile)
    /\AF-O[A-Z0-9]{3}\z/i,

    # Vanuatu (Civil Aviation Authority)
    /\AYJ-[A-Z0-9]{2,3}\z/i,

    # East Timor (Civil Aviation Division)
    /\AZZ-[A-Z0-9]{3}\z/i,

    # Montenegro (Civil Aviation Agency)
    /\A4O-[A-Z0-9]{3}\z/i,

    # Kosovo (Civil Aviation Authority)
    /\AZ6-[A-Z0-9]{3}\z/i,

    # Andorra (Civil Aviation Authority)
    /\AC3-[A-Z0-9]{3}\z/i,

    # Liechtenstein (Civil Aviation Authority)
    /\ALX[A-Z0-9]{1,4}\z/i,

    # San Marino (Civil Aviation Authority)
    /\AT7-[A-Z0-9]{3}\z/i,

    # Moldova (Civil Aviation Authority)
    /\AER-[A-Z0-9]{3}\z/i,

    # North Macedonia (Civil Aviation Agency)
    /\AZ3-[A-Z0-9]{3}\z/i,

    # Bosnia and Herzegovina (Civil Aviation Authority)
    /\AE7-[A-Z0-9]{3}\z/i,

    # Faroe Islands (Civil Aviation Administration)
    /\AOY-[A-Z0-9]{3}\z/i,

    # Greenland (Civil Aviation Administration)
    /\AOY-[A-Z0-9]{3}\z/i,

    # Gibraltar (Civil Aviation Authority)
    /\AZB[A-Z0-9]{1,3}\z/i,

    # Guernsey (Directorate of Civil Aviation)
    /\A2-[A-Z0-9]{4}\z/i,

    # Isle of Man (Aircraft Registry)
    /\AM-[A-Z0-9]{4}\z/i,

  ]

  def validate_each(record, attribute, value)
    unless value =~ Regexp.union(REGISTRATION_PATTERNS)
      record.errors[attribute] << (options[:message] || "is not a valid aircraft registration")
    end
  end
end