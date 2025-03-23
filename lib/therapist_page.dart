import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class Therapist {
  final int id;
  final String name;
  final String specialization;
  final int experience;
  final String contact;
  final String? photoUrl;
  final String? bio;

  Therapist({
    required this.id,
    required this.name,
    required this.specialization,
    required this.experience,
    required this.contact,
    this.photoUrl,
    this.bio,
  });
}

class TherapistPage extends StatefulWidget {
  const TherapistPage({Key? key}) : super(key: key);

  @override
  TherapistPageState createState() => TherapistPageState();
}

class TherapistPageState extends State<TherapistPage> {
  // Sample list of therapists
  final List<Therapist> _therapists = [
    Therapist(
      id: 1,
      name: "Dr. Sarah Johnson",
      specialization: "Anxiety & Depression",
      experience: 8,
      contact: "sarah.johnson@example.com",
      photoUrl: "https://randomuser.me/api/portraits/women/44.jpg",
      bio: "Dr. Johnson specializes in cognitive behavioral therapy for anxiety and depression. She has helped hundreds of patients develop effective coping strategies.",
    ),
    Therapist(
      id: 2,
      name: "Dr. Michael Chen",
      specialization: "Trauma & PTSD",
      experience: 12,
      contact: "michael.chen@example.com",
      photoUrl: "https://randomuser.me/api/portraits/men/32.jpg",
      bio: "With over a decade of experience in trauma therapy, Dr. Chen uses a combination of EMDR and cognitive processing therapy to help patients heal.",
    ),
    Therapist(
      id: 3,
      name: "Dr. Emily Rodriguez",
      specialization: "Family Therapy",
      experience: 10,
      contact: "emily.rodriguez@example.com",
      photoUrl: "https://randomuser.me/api/portraits/women/68.jpg",
      bio: "Dr. Rodriguez helps families improve communication and resolve conflicts through structured therapy sessions and evidence-based interventions.",
    ),
    Therapist(
      id: 4,
      name: "Dr. James Wilson",
      specialization: "Cognitive Behavioral Therapy",
      experience: 15,
      contact: "james.wilson@example.com",
      photoUrl: "https://randomuser.me/api/portraits/men/52.jpg",
      bio: "A specialist in CBT, Dr. Wilson helps patients challenge negative thought patterns and develop healthier perspectives on life's challenges.",
    ),
    Therapist(
      id: 5,
      name: "Dr. Aisha Patel",
      specialization: "Stress Management",
      experience: 7,
      contact: "aisha.patel@example.com",
      photoUrl: "https://randomuser.me/api/portraits/women/37.jpg",
      bio: "Dr. Patel focuses on helping clients develop practical stress management techniques and build resilience for better mental wellbeing.",
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: const Text(
          'Available Therapists',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _buildTherapistList(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Text(
            "Professional Support",
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            "Browse our directory of licensed therapists",
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildTherapistList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      itemCount: _therapists.length,
      itemBuilder: (context, index) {
        final therapist = _therapists[index];
        return _buildTherapistCard(therapist);
      },
    );
  }

  Widget _buildTherapistCard(Therapist therapist) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: () => _showTherapistDetails(therapist),
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            // Therapist photo
            SizedBox(
              height: 180,
              width: double.infinity,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                child: therapist.photoUrl != null
                    ? Image.network(
                        therapist.photoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          color: Colors.blue.shade100,
                          child: const Center(
                            child: Icon(Icons.person, size: 50, color: Colors.blue),
                          ),
                        ),
                      )
                    : Container(
                        color: Colors.blue.shade100,
                        child: const Center(
                          child: Icon(Icons.person, size: 50, color: Colors.blue),
                        ),
                      ),
              ),
            ),
            
            // Therapist info
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          therapist.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          "ID: ${therapist.id}",
                          style: TextStyle(
                            color: Colors.blue.shade800,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildInfoRow(Icons.psychology, therapist.specialization),
                  const SizedBox(height: 4),
                  _buildInfoRow(Icons.star, "${therapist.experience} years experience"),
                  const SizedBox(height: 16),
                  
                  // View profile button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () => _showTherapistDetails(therapist),
                      child: const Text('View Details'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 14, color: Colors.grey[800]),
          ),
        ),
      ],
    );
  }

  void _showTherapistDetails(Therapist therapist) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildTherapistDetailsSheet(therapist),
    );
  }

  Widget _buildTherapistDetailsSheet(Therapist therapist) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar for dragging
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Scrollable content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  children: [
                    // Profile header
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Profile image
                        ClipRRect(
                          borderRadius: BorderRadius.circular(70),
                          child: SizedBox(
                            width: 100,
                            height: 100,
                            child: therapist.photoUrl != null
                                ? Image.network(
                                    therapist.photoUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => Container(
                                      color: Colors.blue.shade100,
                                      child: const Center(
                                        child: Icon(Icons.person, size: 40, color: Colors.blue),
                                      ),
                                    ),
                                  )
                                : Container(
                                    color: Colors.blue.shade100,
                                    child: const Center(
                                      child: Icon(Icons.person, size: 40, color: Colors.blue),
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 20),
                        // Name and details
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                therapist.name,
                                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                therapist.specialization,
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(Icons.star, size: 16, color: Colors.amber[700]),
                                  const SizedBox(width: 4),
                                  Text(
                                    "${therapist.experience} years experience",
                                    style: TextStyle(color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // About section
                    const Text(
                      "About",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      therapist.bio ?? "No bio available",
                      style: TextStyle(
                        height: 1.5,
                        color: Colors.grey[800],
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Contact information
                    const Text(
                      "Contact Information",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: therapist.contact)).then((_) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Email copied to clipboard')),
                          );
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.email_outlined, color: Colors.blue[700]),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                therapist.contact,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const Icon(Icons.content_copy, color: Colors.grey, size: 18),
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Single contact button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.email_outlined),
                        label: const Text('Contact Therapist'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: therapist.contact)).then((_) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Email address copied to clipboard'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}