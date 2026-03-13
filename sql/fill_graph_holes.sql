-- ============================================================
-- Fill wikilink graph holes: 3 missing team documents
-- The 21 archetypes already exist (titles have spaces but 
-- paths resolve correctly via wikilink → filename matching)
-- ============================================================

BEGIN;

INSERT INTO documents (title, path, frontmatter, content, created_at, modified_at) VALUES

-- 1. LegalandEthicsTeam
('LegalandEthicsTeam',
 'Areas/Eckenrode Muziekopname/Legal/LegalandEthicsTeam.md',
 '{"Department Head": "[[JMaxwellCharbourne]]", "Lifestage": "🌱 Seed", "title": "LegalandEthicsTeam"}',
 $BODY$# Legal and Ethics Team
**Purpose**: J. Maxwell Charbourne's team ensures EM operates within legal and ethical frameworks, protecting intellectual property and navigating the complex governance landscape of AI-driven creative media.

- **Intellectual Property Specialist**: [[CarlaVelasquez]] – Manages EM's IP portfolio, ensuring creative works and AI-generated content are properly protected and licensed.
- **Compliance Officer**: [[DavidRhodes]] – Monitors regulatory developments in AI governance and ensures EM's operations comply with evolving legal standards.
- **Ethics Advisor**: [[RachelGreen]] – Provides ethical guidance on AI development practices, content decisions, and the intersection of technology and human values.

☎️ People Directory:
* [[CarlaVelasquez]]
* [[DavidRhodes]]
* [[RachelGreen]]
$BODY$, NOW(), NOW()),

-- 2. MarketingCommunications
('MarketingCommunications',
 'Areas/Eckenrode Muziekopname/ContentandBrandingOffice/MarketingCommunications.md',
 '{"Department Head": "[[SylviaInkweaver]]", "Lifestage": "🌱 Seed", "title": "MarketingCommunications"}',
 $BODY$# Marketing Communications
**Purpose**: Handles public relations and external communications for EM, ensuring the company's message reaches the right audiences with clarity and consistency.

- **Public Relations Associate**: [[LaraCortes]] – Manages media relations, press outreach, and public-facing communications for EM's projects and announcements.

☎️ People Directory:
* [[LaraCortes]]
$BODY$, NOW(), NOW()),

-- 3. TechnicalDevelopmentOffice
('TechnicalDevelopmentOffice',
 'Areas/Eckenrode Muziekopname/Engineering/TechnicalDevelopmentOffice.md',
 '{"Department Head": "[[ElianaRiviera]]", "Lifestage": "🌱 Seed", "title": "TechnicalDevelopmentOffice"}',
 $BODY$# Technical Development Office
**Purpose**: Eliana Riviera's core engineering team builds and maintains EM's technical infrastructure, including T.A.S.K.S., the AF64 framework, and all supporting systems. This is where vision becomes architecture and architecture becomes running code.

- **AI Architect**: [[SamirKhanna]] – Designs the high-level AI systems architecture, ensuring T.A.S.K.S. and AF64 components integrate coherently.
- **DevOps Engineer**: [[MorganFields]] – Manages deployment pipelines, infrastructure reliability, and the operational health of EM's server ecosystem.
- **Systems Engineer**: [[CaseyHan]] – Handles systems-level engineering, networking, and the low-level infrastructure that everything runs on.
- **Full-Stack Developer**: [[DevinPark]] – Builds end-to-end features across EM's web applications, from database to UI.
- **Backend/QA Engineer**: [[DanielleGreen]] – Develops backend services and maintains quality assurance processes across the engineering pipeline.
- **Data Scientist/Security**: [[SanjayPatel]] – Handles data analysis, model evaluation, and security auditing for EM's technical stack.
- **Cloud Architect**: [[IsaacMiller]] – Designs and manages EM's cloud infrastructure, ensuring scalability and cost efficiency.
- **AI Systems Engineer**: [[ElisePark]] – Specializes in AI model integration and the technical plumbing that connects intelligence to infrastructure.

☎️ People Directory:
* [[SamirKhanna]]
* [[MorganFields]]
* [[CaseyHan]]
* [[DevinPark]]
* [[DanielleGreen]]
* [[SanjayPatel]]
* [[IsaacMiller]]
* [[ElisePark]]
$BODY$, NOW(), NOW());

COMMIT;
